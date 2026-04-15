defmodule Busybody.ClientTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Busybody.Client

  describe "build_payload/1" do
    test "builds registration payload from opts" do
      payload = Client.build_payload(name: "myapp", port: 4000, host: "devbox")

      assert payload.name == "myapp"
      assert payload.port == 4000
      assert payload.host == "devbox"
      assert is_binary(payload.pid)
    end

    test "defaults host to system hostname" do
      payload = Client.build_payload(name: "myapp", port: 4000)
      {:ok, hostname} = :inet.gethostname()
      assert payload.host == to_string(hostname)
    end

    test "uses system pid" do
      payload = Client.build_payload(name: "myapp", port: 4000)
      assert payload.pid == System.pid() |> to_string()
    end
  end

  describe "resolve_port/1" do
    test "returns port from explicit opt" do
      assert Client.resolve_port(port: 4567) == 4567
    end

    test "raises when neither port nor endpoint given" do
      assert_raise ArgumentError, ~r/requires either/, fn ->
        Client.resolve_port(name: "myapp")
      end
    end
  end
end
