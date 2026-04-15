defmodule Busybody.HealthCheckerTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Busybody.Registry
  alias Busybody.HealthChecker

  setup do
    registry = start_supervised!({Registry, name: :"registry_#{System.unique_integer()}"})
    %{registry: registry}
  end

  describe "check_all/1" do
    test "prunes apps with unreachable ports", %{registry: registry} do
      Registry.register(registry, %{
        name: "dead_app",
        port: 59999,
        pid: "1",
        host: "127.0.0.1"
      })

      assert [_] = Registry.list(registry)
      HealthChecker.check_all(registry)
      assert [] = Registry.list(registry)
    end

    test "keeps apps with reachable ports", %{registry: registry} do
      {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(listen)

      Registry.register(registry, %{
        name: "live_app",
        port: port,
        pid: "1",
        host: "127.0.0.1"
      })

      HealthChecker.check_all(registry)

      assert [app] = Registry.list(registry)
      assert app.name == "live_app"

      :gen_tcp.close(listen)
    end

    test "prunes only dead apps from a mix", %{registry: registry} do
      {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(listen)

      Registry.register(registry, %{name: "alive", port: port, pid: "1", host: "127.0.0.1"})
      Registry.register(registry, %{name: "dead", port: 59998, pid: "2", host: "127.0.0.1"})

      HealthChecker.check_all(registry)

      apps = Registry.list(registry)
      assert length(apps) == 1
      assert hd(apps).name == "alive"

      :gen_tcp.close(listen)
    end
  end
end
