defmodule Worker do
  require Logger
  use GenServer

  def start_link(id) do
    GenServer.start_link(__MODULE__, id)
  end

  @impl true
  def init(id) do
    Dispatcher.worker_idle(self())

    {:ok,
     %{
       worker_id: id
     }}
  end

  @impl true
  def handle_cast({:run_job, job}, state) do
    Logger.info("Worker #{inspect(state.worker_id)} starting job, sleeping for
      #{inspect(job.sleep_for)}ms")
    Dispatcher.worker_busy(self())
    Process.sleep(job.sleep_for)
    Logger.info("Worker #{inspect(state.worker_id)} finished job")
    Dispatcher.worker_idle(self())
    {:noreply, state}
  end
end
