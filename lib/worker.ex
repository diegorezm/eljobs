defmodule Worker do
  use GenServer

  def start_link(job) do
    GenServer.start_link(__MODULE__, job)
  end

  @impl true
  def init(job) do
    state = %{
      worker_id: UUID.uuid4(),
      job: Job.update_status(job, :running),
      started_at: DateTime.utc_now()
    }

    send(self(), :run_job)

    {:ok, state}
  end

  @impl true
  def handle_info(:run_job, %{job: job} = state) do
    Process.sleep(job.sleep_for)

    updated_job =
      Job.update_status(job, :completed)

    {:stop, :normal, %{state | job: updated_job}}
  end
end
