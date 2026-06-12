defmodule BusybodyWeb.DirectoryLiveTest do
  @moduledoc false
  use BusybodyWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup do
    apps = Busybody.Registry.list()
    Enum.each(apps, fn app -> Busybody.Registry.deregister(app.name) end)
    :ok
  end

  test "renders empty state", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ "busybody"
    assert html =~ "0 SERVICES"
    assert html =~ "No services registered"
  end

  test "shows registered apps with OK status", %{conn: conn} do
    Busybody.Registry.register(%{name: "paperclip", port: 4829, pid: "100", host: "devbox"})

    {:ok, _view, html} = live(conn, "/")
    assert html =~ "paperclip"
    assert html =~ "4829"
    assert html =~ "devbox"
    # freshly registered -> OK, encoded as glyph + word, not color alone
    assert html =~ "OK"
    assert html =~ "1 SERVICE"
  end

  test "updates in real-time when app registers", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    Busybody.Registry.register(%{name: "newapp", port: 4500, pid: "200", host: "localhost"})

    assert render(view) =~ "newapp"
  end

  test "removes app when deregistered", %{conn: conn} do
    Busybody.Registry.register(%{name: "dying", port: 4600, pid: "300", host: "localhost"})
    {:ok, view, html} = live(conn, "/")
    assert html =~ "dying"

    Busybody.Registry.deregister("dying")

    refute render(view) =~ "dying"
  end
end
