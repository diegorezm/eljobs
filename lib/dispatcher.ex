defmodule Dispatcher do
  @max_retries 1

  require Logger
  use GenServer

  @stats_table :dispatcher_stats

  def dispatch(job) do
    GenServer.cast(__MODULE__, {:dispatch, job})
  end

  def get_stats() do
    case :ets.lookup(@stats_table, :snapshot) do
      [{:snapshot, stats}] -> stats
      [] -> %{queued_jobs: 0, busy_workers: 0, idle_workers: 0, jobs_completed: 0}
    end
  end

  def worker_busy(worker) do
    GenServer.cast(__MODULE__, {:worker_busy, worker})
  end

  def worker_idle(worker, result \\ nil) do
    GenServer.cast(__MODULE__, {:worker_idle, worker, result})
  end

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_) do
    :ets.new(@stats_table, [:set, :public, :named_table])

    dispatcher_state = %{
      idle_workers: MapSet.new(),
      busy_workers: MapSet.new(),
      queue: :queue.new(),
      dlq: :queue.new(),
      jobs_completed: 0
    }

    update_stats(dispatcher_state)
    {:ok, dispatcher_state}
  end

  @impl true
  def handle_cast({:worker_idle, worker, result}, state) do
    state = update_state_on_job_result(result, state)

    state =
      state
      |> Map.update!(:idle_workers, &MapSet.put(&1, worker))
      |> Map.update!(:busy_workers, &MapSet.delete(&1, worker))

    state = call_worker_if_queue_not_empty(worker, state)

    update_stats(state)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:worker_busy, worker}, state) do
    state =
      state
      |> Map.update!(:idle_workers, &MapSet.delete(&1, worker))
      |> Map.update!(:busy_workers, &MapSet.put(&1, worker))

    update_stats(state)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:dispatch, job}, state) do
    state = do_dispatch(job, state)
    update_stats(state)
    {:noreply, state}
  end

  defp do_dispatch(%Job{} = job, state) do
    case MapSet.to_list(state.idle_workers) do
      [] ->
        # Logger.info("No idle workers, queuing job")
        %{state | queue: :queue.in(job, state.queue)}

      [worker | _rest] ->
        Logger.info("Dispatching job to worker #{inspect(worker)}")
        GenServer.cast(worker, {:run_job, job})

        state
        |> Map.update!(:idle_workers, &MapSet.delete(&1, worker))
        |> Map.update!(:busy_workers, &MapSet.put(&1, worker))
    end
  end

  defp call_worker_if_queue_not_empty(worker, state) do
    case :queue.out(state.queue) do
      {{:value, job}, rest} ->
        GenServer.cast(worker, {:run_job, job})
        %{state | queue: rest}

      {:empty, _} ->
        call_worker_if_dlq_not_empty(worker, state)
    end
  end

  defp update_state_on_job_result(result, state) do
    case result do
      nil ->
        state

      job ->
        case job.status do
          :completed ->
            Logger.info("Job #{inspect(job.id)} finished with status #{job.status}")

            state
            |> Map.update!(:jobs_completed, &(&1 + 1))

          :failed ->
            Logger.error("Job #{inspect(job.id)} failed: #{inspect(job.result)}")

            Logger.info(
              "Job #{inspect(job.id)} added to DLQ with #{inspect(job.retries)} retries so far."
            )

            state
            |> Map.update!(:dlq, &:queue.in(job, &1))
        end
    end
  end

  defp call_worker_if_dlq_not_empty(worker, state) do
    case :queue.out(state.dlq) do
      {{:value, job}, rest} ->
        if job.retries < @max_retries do
          Logger.info("Retrying job #{inspect(job.id)}, attempt #{job.retries + 1}")
          GenServer.cast(worker, {:run_job, %{job | retries: job.retries + 1}})
        else
          Logger.error("Job #{inspect(job.id)} exceeded max retries, dropping")
        end

        %{state | dlq: rest}

      {:empty, _} ->
        state
    end
  end

  defp update_stats(state) do
    stats = %{
      queued_jobs: :queue.len(state.queue),
      busy_workers: MapSet.size(state.busy_workers),
      idle_workers: MapSet.size(state.idle_workers),
      jobs_completed: state.jobs_completed,
      dlq_jobs: :queue.len(state.dlq)
    }

    :ets.insert(@stats_table, {:snapshot, stats})
  end
end
