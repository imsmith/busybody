defmodule Busybody.IntegrationTest do
  @moduledoc false
  use BusybodyWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup do
    apps = Busybody.Registry.list()
    Enum.each(apps, fn app -> Busybody.Registry.deregister(app.name) end)
    :ok
  end

  test "full round trip: API register -> LiveView shows app -> health check prunes", %{conn: conn} do
    # Start a fake app listener
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)

    # Register via API
    conn
    |> put_req_header("content-type", "application/json")
    |> post("/api/register", %{
      "name" => "fakeapp",
      "port" => port,
      "pid" => "99999",
      "host" => "127.0.0.1"
    })

    # LiveView shows the app
    {:ok, _view, html} = live(build_conn(), "/")
    assert html =~ "fakeapp"
    assert html =~ "#{port}"

    # Kill the listener, run health check
    :gen_tcp.close(listen)
    Busybody.HealthChecker.check_all()

    # App should be gone
    assert [] = Busybody.Registry.list()
  end
end
