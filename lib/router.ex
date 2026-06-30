defmodule Router do
  use Plug.Router
  plug(:match)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason)
  plug(:dispatch)

  post "/jobs" do
    %{"payload" => payload} = conn.body_params
    secret = Application.get_env(:eljobs, :secret)

    job =
      Job.new(
        work: fn -> {:ok, Plug.Crypto.MessageEncryptor.encrypt(payload, secret, "UNUSED")} end
      )

    Dispatcher.dispatch(job)
    send_resp(conn, 202, Jason.encode!(%{job_id: job.id, status: "queued"}))
  end

  get "/stats" do
    stats = Dispatcher.get_stats()
    send_resp(conn, 200, Jason.encode!(stats))
  end
end
