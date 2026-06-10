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

  test "degrades gracefully when application.ex has no children assignment" do
    # phx_test_project generates an application.ex with `children = [...]`.
    # We replace it wholesale via the Rewrite API to simulate an app that uses
    # an inlined Supervisor.start_link (no `children =` binding at all).
    no_children_app = """
    defmodule Test.Application do
      @moduledoc false
      use Application

      @impl true
      def start(_type, _args) do
        Supervisor.start_link([], strategy: :one_for_one, name: Test.Supervisor)
      end
    end
    """

    igniter =
      phx_test_project()
      |> then(fn ign ->
        source = Rewrite.source!(ign.rewrite, "lib/test/application.ex")
        new_source = Rewrite.Source.update(source, :content, no_children_app)
        %{ign | rewrite: Rewrite.update!(ign.rewrite, new_source)}
      end)
      |> Igniter.compose_task("busybody.install", [])

    # Dep patch is present in the pending igniter (before apply).
    igniter
    |> assert_has_patch("mix.exs", """
    + |      {:busybody, [path: "../busybody", only: :dev]},
    """)

    # Must not raise; warning emitted about missing children assignment.
    {:ok, _result, %{warnings: warnings}} = apply_igniter(igniter)
    assert Enum.any?(warnings, &(&1 =~ "busybody_children"))
  end
end
