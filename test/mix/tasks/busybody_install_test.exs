defmodule Mix.Tasks.Busybody.InstallTest do
  @moduledoc false
  use ExUnit.Case, async: true
  import Igniter.Test

  test "adds the busybody path dep scoped to :dev" do
    phx_test_project()
    |> Igniter.compose_task("busybody.install", [])
    |> assert_has_patch("mix.exs", """
    + |      {:busybody, [path: "../busybody", only: :dev]},
    """)
  end

  test "appends ++ busybody_children() to the children list" do
    phx_test_project()
    |> Igniter.compose_task("busybody.install", [])
    |> assert_has_patch("lib/test/application.ex", """
    + |    ] ++ busybody_children()
    """)
  end

  test "adds the Code.ensure_loaded?-guarded helper" do
    phx_test_project()
    |> Igniter.compose_task("busybody.install", ["--name", "my_app"])
    |> assert_has_patch("lib/test/application.ex", """
    + |  defp busybody_children do
    + |    if Code.ensure_loaded?(Busybody.Client) do
    + |      [{Busybody.Client, name: "my_app", endpoint: TestWeb.Endpoint}]
    + |    else
    + |      []
    + |    end
    + |  end
    """)
  end

  test "is idempotent — a second run does not double-append or duplicate the helper" do
    {:ok, after_first, _} =
      phx_test_project()
      |> Igniter.compose_task("busybody.install", [])
      |> apply_igniter()

    after_first
    |> Igniter.compose_task("busybody.install", [])
    |> assert_unchanged()
  end
end
