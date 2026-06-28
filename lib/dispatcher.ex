defmodule Dispatcher do
  use GenServer

  def dispatch(job) do
    GenServer.cast(__MODULE__, {:dispatch, job})
  end

  def worker_busy(worker) do
    GenServer.cast(__MODULE__, {:worker_busy, worker})
  end

  def worker_idle(worker) do
    GenServer.cast(__MODULE__, {:worker_idle, worker})
  end

  def start_link() do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_) do
    dispatcher_state = %{
      idle_workers: MapSet.new(),
      busy_workers: MapSet.new(),
      queue: :queue.new()
    }

    {:ok, dispatcher_state}
  end

  @impl true
  def handle_cast({:worker_idle, worker}, state) do
    state =
      state
      |> Map.update!(:idle_workers, &MapSet.put(&1, worker))
      |> Map.update!(:busy_workers, &MapSet.delete(&1, worker))

    state =
      case :queue.out(state.queue) do
        {{:value, job}, rest} ->
          GenServer.cast(worker, {:run_job, job})
          %{state | queue: rest}

        {:empty, _} ->
          state
      end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:worker_busy, worker}, state) do
    state =
      state
      |> Map.update!(:idle_workers, &MapSet.delete(&1, worker))
      |> Map.update!(:busy_workers, &MapSet.put(&1, worker))

    {:noreply, state}
  end

  @impl true
  def handle_cast({:dispatch, job}, state) do
    {:noreply, do_dispatch(job, state)}
  end

  defp do_dispatch(job, state) do
    case MapSet.to_list(state.idle_workers) do
      [] ->
        %{state | queue: :queue.in(job, state.queue)}

      [worker | _rest] ->
        GenServer.cast(worker, {:run_job, job})
        state
    end
  end
end
