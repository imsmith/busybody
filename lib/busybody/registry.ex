defmodule Busybody.Registry do
  @moduledoc """
  GenServer that holds an in-memory registry of running apps.

  Each entry is keyed by app name and carries: name, port, pid, host,
  registered_at, last_seen. Broadcasts changes via Phoenix.PubSub so
  LiveView subscribers can react in real-time.
  """

  use GenServer

  @pubsub Busybody.PubSub
  @topic "registry"

  # Client API

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  def register(server \\ __MODULE__, attrs) do
    GenServer.call(server, {:register, attrs})
  end

  def deregister(server \\ __MODULE__, name) do
    GenServer.call(server, {:deregister, name})
  end

  def list(server \\ __MODULE__) do
    GenServer.call(server, :list)
  end

  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
  end

  # Server callbacks

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:register, attrs}, _from, state) do
    now = DateTime.utc_now()

    entry = %{
      name: attrs.name,
      port: attrs.port,
      pid: attrs.pid,
      host: attrs.host,
      registered_at: get_in(state, [attrs.name, :registered_at]) || now,
      last_seen: now
    }

    new_state = Map.put(state, attrs.name, entry)
    broadcast({:app_registered, entry})
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:deregister, name}, _from, state) do
    if Map.has_key?(state, name) do
      broadcast({:app_deregistered, name})
    end

    {:reply, :ok, Map.delete(state, name)}
  end

  @impl true
  def handle_call(:list, _from, state) do
    {:reply, Map.values(state), state}
  end

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, message)
  end
end
