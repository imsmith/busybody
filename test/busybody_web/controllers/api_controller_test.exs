defmodule BusybodyWeb.ApiControllerTest do
  @moduledoc false

  use BusybodyWeb.ConnCase

  setup do
    start_supervised!(Busybody.Registry)
    apps = Busybody.Registry.list()
    Enum.each(apps, fn app -> Busybody.Registry.deregister(app.name) end)
    :ok
  end

  describe "POST /api/register" do
    test "registers an app", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/register", %{
          "name" => "testapp",
          "port" => 4000,
          "pid" => "12345",
          "host" => "devbox"
        })

      assert json_response(conn, 200) == %{"status" => "ok"}

      apps = Busybody.Registry.list()
      assert length(apps) == 1
      assert hd(apps).name == "testapp"
      assert hd(apps).host == "devbox"
    end

    test "returns 422 when name is missing", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/register", %{"port" => 4000, "pid" => "1", "host" => "x"})

      assert json_response(conn, 422)
    end
  end

  describe "GET /api/apps" do
    test "returns empty list when nothing registered", %{conn: conn} do
      conn = get(conn, "/api/apps")
      assert json_response(conn, 200) == %{"apps" => []}
    end

    test "returns registered apps", %{conn: conn} do
      Busybody.Registry.register(%{name: "app1", port: 4000, pid: "1", host: "localhost"})

      conn = get(conn, "/api/apps")
      %{"apps" => [app]} = json_response(conn, 200)
      assert app["name"] == "app1"
      assert app["port"] == 4000
    end
  end
end
