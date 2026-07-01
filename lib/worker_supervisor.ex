defmodule WorkerSupervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(worker_count) do
    children =
      Enum.map(1..worker_count, fn i ->
        Supervisor.child_spec({Worker, UUID.uuid4()}, id: {Worker, i})
      end)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
