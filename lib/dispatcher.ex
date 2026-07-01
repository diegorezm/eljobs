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

  def start_link(worker_count) do
    GenServer.start_link(__MODULE__, worker_count, name: __MODULE__)
  end

  @impl true
  def init(worker_count) do
    :ets.new(@stats_table, [:set, :public, :named_table])

    dispatcher_state = %{
      worker_count: worker_count,
      started_at: DateTime.utc_now(),
      idle_workers: MapSet.new(),
      busy_workers: MapSet.new(),
      queue: :queue.new(),
      dlq: :queue.new(),
      total_wait_ms: 0,
      total_exec_time_ms: 0,
      jobs_completed: 0,
      peak_queue: 0,
      total_utilization_samples: 0,
      utilization_sample_count: 0
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
    state = sample_utilization(state)
    update_stats(state)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:worker_busy, worker}, state) do
    state =
      state
      |> Map.update!(:idle_workers, &MapSet.delete(&1, worker))
      |> Map.update!(:busy_workers, &MapSet.put(&1, worker))

    state = sample_utilization(state)
    update_stats(state)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:dispatch, job}, state) do
    state = do_dispatch(job, state)
    state = sample_utilization(state)
    update_stats(state)
    {:noreply, state}
  end

  defp do_dispatch(%Job{} = job, state) do
    case MapSet.to_list(state.idle_workers) do
      [] ->
        # Logger.info("No idle workers, queuing job")
        new_queue = :queue.in(job, state.queue)
        current_depth = :queue.len(new_queue)
        %{state | queue: new_queue, peak_queue: max(current_depth, state.peak_queue)}

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
            wait_ms = DateTime.diff(job.started_at, job.created_at, :microsecond)
            exec_time = DateTime.diff(job.ended_at, job.started_at, :microsecond)

            state
            |> Map.update!(:jobs_completed, &(&1 + 1))
            |> Map.update!(:total_wait_ms, &(&1 + wait_ms))
            |> Map.update!(:total_exec_time_ms, &(&1 + exec_time))

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
    uptime_seconds = DateTime.diff(DateTime.utc_now(), state.started_at, :second)

    avg_wait_ms =
      if state.jobs_completed > 0 do
        div(state.total_wait_ms, state.jobs_completed)
      else
        0
      end

    avg_exec_time_ms =
      if state.jobs_completed > 0 do
        div(state.total_exec_time_ms, state.jobs_completed)
      else
        0
      end

    throughput =
      if uptime_seconds > 0 do
        state.jobs_completed / uptime_seconds
      else
        0
      end

    current_utilization =
      if state.worker_count > 0 do
        MapSet.size(state.busy_workers) / state.worker_count
      else
        0
      end

    avg_utilization =
      if state.utilization_sample_count > 0 do
        state.total_utilization_samples / state.utilization_sample_count
      else
        0
      end

    stats = %{
      peak_queue: state.peak_queue,
      queued_jobs: :queue.len(state.queue),
      busy_workers: MapSet.size(state.busy_workers),
      idle_workers: MapSet.size(state.idle_workers),
      jobs_completed: state.jobs_completed,
      dlq_jobs: :queue.len(state.dlq),
      avg_wait_ms: avg_wait_ms,
      throughput: Float.round(throughput * 1.0, 2),
      avg_exec_time_ms_ms: avg_exec_time_ms,
      avg_exec_time_ms: avg_exec_time_ms,
      current_worker_utilization: Float.round(current_utilization * 1.0, 2),
      avg_worker_utilization: Float.round(avg_utilization * 1.0, 2)
    }

    :ets.insert(@stats_table, {:snapshot, stats})
  end

  defp sample_utilization(state) do
    sample = MapSet.size(state.busy_workers) / state.worker_count

    state
    |> Map.update!(:total_utilization_samples, &(&1 + sample))
    |> Map.update!(:utilization_sample_count, &(&1 + 1))
  end
end
