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
end
