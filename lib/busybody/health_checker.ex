defmodule Busybody.HealthChecker do
  @moduledoc """
  Periodically TCP-probes each registered app and prunes unreachable entries.

  Runs every 30 seconds by default. On each tick it iterates all entries in the
  Registry and attempts a TCP connection to `host:port`. Any entry that fails
  the connect is deregistered immediately.
  """

  use GenServer

  @default_interval :timer.seconds(30)
  @tcp_timeout :timer.seconds(2)

  @doc "Start the health checker GenServer."
  def start_link(opts) do
    interval = Keyword.get(opts, :interval, @default_interval)
    registry = Keyword.get(opts, :registry, Busybody.Registry)
    GenServer.start_link(__MODULE__, %{interval: interval, registry: registry}, name: __MODULE__)
  end

  @doc """
  Probe every app in the registry and deregister those whose port is unreachable.

  Accepts an explicit registry pid/name; defaults to `Busybody.Registry`.
  """
  def check_all(registry \\ Busybody.Registry) do
    apps = Busybody.Registry.list(registry)

    Enum.each(apps, fn app ->
      host = to_charlist(app.host)

      case :gen_tcp.connect(host, app.port, [], @tcp_timeout) do
        {:ok, socket} ->
          :gen_tcp.close(socket)

        {:error, _} ->
          Busybody.Registry.deregister(registry, app.name)
      end
    end)
  end

  @impl GenServer
  def init(state) do
    schedule_check(state.interval)
    {:ok, state}
  end

  @impl GenServer
  def handle_info(:check, state) do
    check_all(state.registry)
    schedule_check(state.interval)
    {:noreply, state}
  end

  defp schedule_check(interval) do
    Process.send_after(self(), :check, interval)
  end
end
