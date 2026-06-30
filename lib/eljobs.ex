defmodule Eljobs do
  use Application

  def start(_type, _args) do
    create_app_secret()

    children = [
      Dispatcher,
      WorkerSupervisor,
      {Bandit, plug: Router, port: 4000}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  defp create_app_secret() do
    secret_key_base = "538dad37c58a1caf3011bd5f733af870"
    encrypted_cookie_salt = "encrypted cookie"

    secret =
      Plug.Crypto.KeyGenerator.generate(
        secret_key_base,
        encrypted_cookie_salt
      )

    Application.put_env(:eljobs, :secret, secret)
  end
end
