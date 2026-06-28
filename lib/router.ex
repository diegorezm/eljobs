defmodule Router do
  use Plug.Router
  plug(:match)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason)
  plug(:dispatch)

  post "/jobs" do
    %{"sleep_for" => sleep_for} = conn.body_params
    Dispatcher.dispatch(%{sleep_for: sleep_for})
    send_resp(conn, 202, "job queued")
  end
end
