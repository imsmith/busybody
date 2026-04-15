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
  @max_concurrency 10

  @doc "Start the health checker GenServer."
  def start_link(opts) do
    interval = Keyword.get(opts, :interval, @default_interval)
    registry = Keyword.get(opts, :registry, Busybody.Registry)
    GenServer.start_link(__MODULE__, %{interval: interval, registry: registry}, name: __MODULE__)
  end

  @doc """
  Probe every app in the registry and deregister those whose port is unreachable.

  Runs probes concurrently (up to #{@max_concurrency} at a time) so a few
  slow hosts can't stall the entire check cycle.

  Accepts an explicit registry pid/name; defaults to `Busybody.Registry`.
  """
  def check_all(registry \\ Busybody.Registry) do
    apps = Busybody.Registry.list(registry)

    apps
    |> Task.async_stream(
      fn app -> {app.name, probe(app.host, app.port)} end,
      max_concurrency: @max_concurrency,
      timeout: @tcp_timeout + :timer.seconds(1),
      on_timeout: :kill_task
    )
    |> Enum.each(fn
      {:ok, {name, :unreachable}} ->
        Busybody.Registry.deregister(registry, name)

      {:ok, {_name, :ok}} ->
        :ok

      {:exit, _reason} ->
        :ok
    end)
  end

  defp probe(host, port) do
    case :gen_tcp.connect(to_charlist(host), port, [], @tcp_timeout) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        :ok

      {:error, _} ->
        :unreachable
    end
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
