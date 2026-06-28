defmodule Worker do
  use GenServer

  def start_link(id) do
    GenServer.start_link(__MODULE__, id)
  end

  @impl true
  def init(id) do
    {:ok,
     %{
       worker_id: id
     }}
  end

  @impl true
  def handle_cast({:run_job, job}, state) do
    Dispatcher.worker_busy(self())
    Process.sleep(job.sleep_for)
    Dispatcher.worker_idle(self())
    {:noreply, state}
  end
end
