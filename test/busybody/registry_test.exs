defmodule Busybody.RegistryTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Busybody.Registry

  setup do
    registry = start_supervised!({Registry, name: :"registry_#{System.unique_integer()}"})
    %{registry: registry}
  end

  describe "register/2" do
    test "registers an app", %{registry: registry} do
      attrs = %{name: "myapp", port: 4000, pid: "12345", host: "localhost"}
      assert :ok = Registry.register(registry, attrs)
      assert [app] = Registry.list(registry)
      assert app.name == "myapp"
      assert app.port == 4000
      assert app.pid == "12345"
      assert app.host == "localhost"
      assert %DateTime{} = app.registered_at
      assert %DateTime{} = app.last_seen
    end

    test "upserts on duplicate name", %{registry: registry} do
      attrs = %{name: "myapp", port: 4000, pid: "12345", host: "localhost"}
      Registry.register(registry, attrs)

      updated = %{name: "myapp", port: 4001, pid: "12346", host: "localhost"}
      Registry.register(registry, updated)

      assert [app] = Registry.list(registry)
      assert app.port == 4001
      assert app.pid == "12346"
    end

    test "multiple apps coexist", %{registry: registry} do
      Registry.register(registry, %{name: "app1", port: 4000, pid: "1", host: "localhost"})
      Registry.register(registry, %{name: "app2", port: 4001, pid: "2", host: "localhost"})

      apps = Registry.list(registry)
      assert length(apps) == 2
      names = Enum.map(apps, & &1.name) |> Enum.sort()
      assert names == ["app1", "app2"]
    end
  end

  describe "deregister/2" do
    test "removes an app by name", %{registry: registry} do
      Registry.register(registry, %{name: "myapp", port: 4000, pid: "1", host: "localhost"})
      assert :ok = Registry.deregister(registry, "myapp")
      assert [] = Registry.list(registry)
    end

    test "no-op for unknown name", %{registry: registry} do
      assert :ok = Registry.deregister(registry, "unknown")
    end
  end

  describe "list/1" do
    test "returns empty list when no apps registered", %{registry: registry} do
      assert [] = Registry.list(registry)
    end
  end
end
