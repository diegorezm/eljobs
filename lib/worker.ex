defmodule Worker do
  use GenServer

  def start_link(id) do
    GenServer.start_link(__MODULE__, id)
  end

  @impl true
  def init(id) do
    Dispatcher.worker_idle(self())
    {:ok, %{worker_id: id, result: nil}}
  end

  @impl true
  def handle_cast({:run_job, %Job{} = job}, state) do
    Dispatcher.worker_busy(self())
    result = execute(job)
    Dispatcher.worker_idle(self(), result)

    {:noreply, %{state | result: result}}
  end

  defp execute(%Job{} = job) do
    try do
      result = job.work.()
      %{job | status: :completed, result: result, ended_at: DateTime.utc_now()}
    rescue
      e -> %{job | status: :failed, failed_at: DateTime.utc_now(), result: {:error, e}}
    end
  end
end
