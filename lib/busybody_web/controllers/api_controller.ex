defmodule BusybodyWeb.ApiController do
  @moduledoc false

  use BusybodyWeb, :controller

  def register(conn, %{"name" => name, "port" => port, "pid" => pid, "host" => host}) do
    Busybody.Registry.register(%{
      name: name,
      port: port,
      pid: pid,
      host: host
    })

    json(conn, %{status: "ok"})
  end

  def register(conn, _params) do
    conn
    |> put_status(422)
    |> json(%{error: "missing required fields: name, port, pid, host"})
  end

  def index(conn, _params) do
    apps =
      Busybody.Registry.list()
      |> Enum.map(fn app ->
        %{
          name: app.name,
          port: app.port,
          pid: app.pid,
          host: app.host,
          registered_at: DateTime.to_iso8601(app.registered_at),
          last_seen: DateTime.to_iso8601(app.last_seen)
        }
      end)

    json(conn, %{apps: apps})
  end
end
