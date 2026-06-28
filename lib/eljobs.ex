defmodule Eljobs do
  use Application

  def start(_type, _args) do
    children = [
      Dispatcher,
      WorkerSupervisor,
      {Bandit, plug: Router, port: 4000}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
