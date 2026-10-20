defmodule BusybodyWeb.ApiController do
  @moduledoc """
  JSON API for app registration.

  * `POST /api/register` — upsert an app entry (name, port, pid, host, optional group)
  * `GET  /api/apps`     — list all registered apps
  """

  use BusybodyWeb, :controller

  def register(conn, %{"name" => name, "port" => port, "pid" => pid, "host" => host} = params)
      when is_binary(name) and byte_size(name) > 0 and
             is_integer(port) and port in 1..65_535 and
             is_binary(pid) and is_binary(host) and byte_size(host) > 0 do
    # ponytail: group accepts any non-empty string; tighten here when a value policy lands
    case Map.get(params, "group") do
      group when is_nil(group) or (is_binary(group) and byte_size(group) > 0) ->
        attrs = %{name: name, port: port, pid: pid, host: host, group: group}

        case Busybody.Registry.register(attrs) do
          :ok ->
            json(conn, %{status: "ok"})

          {:error, :registry_full} ->
            conn
            |> put_status(503)
            |> json(%{error: "registry full"})
        end

      _ ->
        invalid(conn)
    end
  end

  def register(conn, _params), do: invalid(conn)

  defp invalid(conn) do
    conn
    |> put_status(422)
    |> json(%{
      error:
        "missing or invalid fields: name (string), port (1-65535), pid (string), host (string), group (optional string)"
    })
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
          group: app.group,
          registered_at: DateTime.to_iso8601(app.registered_at),
          last_seen: DateTime.to_iso8601(app.last_seen)
        }
      end)

    json(conn, %{apps: apps})
  end
end
