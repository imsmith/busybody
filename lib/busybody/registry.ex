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
  @max_entries 100

  @typedoc "Fields a caller supplies when registering."
  @type attrs :: %{name: String.t(), port: 1..65_535, pid: String.t(), host: String.t()}

  @typedoc "A stored entry: the supplied fields plus registry timestamps."
  @type entry :: %{
          name: String.t(),
          port: 1..65_535,
          pid: String.t(),
          host: String.t(),
          registered_at: DateTime.t(),
          last_seen: DateTime.t()
        }

  # Client API

  @doc "Start the registry, optionally with a custom `:name`."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Register or update an app entry.

  Upserts by name — a re-registration updates port/pid/host and refreshes
  `last_seen` while preserving the original `registered_at`.

  ## Examples

      iex> {:ok, registry} = Busybody.Registry.start_link(name: :doctest_reg)
      iex> Busybody.Registry.register(registry, %{name: "myapp", port: 4000, pid: "1", host: "localhost"})
      :ok
      iex> [app] = Busybody.Registry.list(registry)
      iex> app.name
      "myapp"

  """
  @spec register(GenServer.server(), attrs()) :: :ok | {:error, :registry_full}
  def register(server \\ __MODULE__, attrs) do
    GenServer.call(server, {:register, attrs})
  end

  @doc """
  Remove an app by name. No-op if the name isn't registered.

  ## Examples

      iex> {:ok, registry} = Busybody.Registry.start_link(name: :doctest_dereg)
      iex> Busybody.Registry.register(registry, %{name: "gone", port: 4000, pid: "1", host: "localhost"})
      iex> Busybody.Registry.deregister(registry, "gone")
      :ok
      iex> Busybody.Registry.list(registry)
      []

  """
  @spec deregister(GenServer.server(), String.t()) :: :ok
  def deregister(server \\ __MODULE__, name) do
    GenServer.call(server, {:deregister, name})
  end

  @doc """
  List all registered apps.

  ## Examples

      iex> {:ok, registry} = Busybody.Registry.start_link(name: :doctest_list)
      iex> Busybody.Registry.list(registry)
      []

  """
  @spec list(GenServer.server()) :: [entry()]
  def list(server \\ __MODULE__) do
    GenServer.call(server, :list)
  end

  @doc "Subscribe to registry change notifications via PubSub."
  @spec subscribe() :: :ok | {:error, term()}
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
    is_update = Map.has_key?(state, attrs.name)

    if not is_update and map_size(state) >= @max_entries do
      {:reply, {:error, :registry_full}, state}
    else
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
