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

    test "stores an optional group", %{registry: registry} do
      Registry.register(registry, %{name: "a", port: 4000, pid: "1", host: "h", group: "infra"})
      Registry.register(registry, %{name: "b", port: 4001, pid: "2", host: "h"})

      assert Enum.find(Registry.list(registry), &(&1.name == "a")).group == "infra"
      assert Enum.find(Registry.list(registry), &(&1.name == "b")).group == nil
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

  describe "capacity" do
    test "rejects new registrations when full", %{registry: registry} do
      for i <- 1..100 do
        :ok =
          Registry.register(registry, %{
            name: "app#{i}",
            port: 4000 + i,
            pid: "#{i}",
            host: "localhost"
          })
      end

      assert {:error, :registry_full} =
               Registry.register(registry, %{
                 name: "overflow",
                 port: 5000,
                 pid: "101",
                 host: "localhost"
               })

      assert length(Registry.list(registry)) == 100
    end

    test "allows upserts when full", %{registry: registry} do
      for i <- 1..100 do
        :ok =
          Registry.register(registry, %{
            name: "app#{i}",
            port: 4000 + i,
            pid: "#{i}",
            host: "localhost"
          })
      end

      assert :ok =
               Registry.register(registry, %{
                 name: "app1",
                 port: 9999,
                 pid: "1",
                 host: "localhost"
               })

      app = Enum.find(Registry.list(registry), &(&1.name == "app1"))
      assert app.port == 9999
    end
  end
end
