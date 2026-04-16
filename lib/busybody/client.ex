defmodule Busybody.Client do
  @moduledoc """
  GenServer for consumer apps to register with the Busybody directory.

  Add to your supervision tree (dev only):

      children = [
        MyAppWeb.Endpoint,
        {Busybody.Client, name: "my_app", endpoint: MyAppWeb.Endpoint}
      ]

  Options:
    * `:name` - app name to register (required)
    * `:endpoint` - Phoenix endpoint module, used to resolve port (required unless `:port` given)
    * `:port` - explicit port (overrides endpoint resolution)
    * `:registry_url` - defaults to "http://localhost:5150"
    * `:host` - defaults to system hostname
  """

  use GenServer
  require Logger

  @default_registry_url "http://localhost:5150"
  @heartbeat_interval :timer.seconds(60)
  @startup_delay :timer.seconds(2)

  @doc "Start the client GenServer. See module docs for available options."
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :process_name, __MODULE__))
  end

  @doc """
  Build the JSON registration payload from the given opts.

  ## Examples

      iex> payload = Busybody.Client.build_payload(name: "demo", port: 4000, host: "devbox")
      iex> payload.name
      "demo"
      iex> payload.port
      4000
      iex> payload.host
      "devbox"
      iex> is_binary(payload.pid)
      true

  """
  def build_payload(opts) do
    {:ok, hostname} = :inet.gethostname()

    %{
      name: Keyword.fetch!(opts, :name),
      port: resolve_port(opts),
      pid: System.pid() |> to_string(),
      host: Keyword.get(opts, :host, to_string(hostname))
    }
  end

  @doc """
  Resolve the port from opts — either an explicit `:port` or by
  querying the `:endpoint` module's HTTP config.

  ## Examples

      iex> Busybody.Client.resolve_port(port: 4567)
      4567

      iex> Busybody.Client.resolve_port(name: "oops")
      ** (ArgumentError) Busybody.Client requires either :port or :endpoint option

  """
  def resolve_port(opts) do
    cond do
      Keyword.has_key?(opts, :port) ->
        Keyword.get(opts, :port)

      Keyword.has_key?(opts, :endpoint) ->
        endpoint = Keyword.get(opts, :endpoint)

        case Keyword.get(endpoint.config(:url, []), :port) do
          port when is_integer(port) and port > 0 ->
            port

          _ ->
            # Get the actual bound port from the running server
            {:ok, {_ip, port}} = endpoint.server_info(:http)
            port
        end

      true ->
        raise ArgumentError, "Busybody.Client requires either :port or :endpoint option"
    end
  end

  @impl true
  def init(opts) do
    state = %{
      opts: opts,
      registry_url: Keyword.get(opts, :registry_url, @default_registry_url),
      heartbeat_interval: Keyword.get(opts, :heartbeat_interval, @heartbeat_interval)
    }

    Process.send_after(self(), :register, @startup_delay)
    {:ok, state}
  end

  @impl true
  def handle_info(:register, state) do
    payload = build_payload(state.opts)
    do_register(state.registry_url, payload)
    schedule_heartbeat(state.heartbeat_interval)
    {:noreply, Map.put(state, :payload, payload)}
  end

  @impl true
  def handle_info(:heartbeat, state) do
    do_register(state.registry_url, state.payload)
    schedule_heartbeat(state.heartbeat_interval)
    {:noreply, state}
  end

  defp do_register(registry_url, payload) do
    url = "#{registry_url}/api/register"
    body = Jason.encode!(payload)

    case :httpc.request(
           :post,
           {to_charlist(url), [], ~c"application/json", to_charlist(body)},
           [timeout: 5000],
           []
         ) do
      {:ok, {{_, 200, _}, _, _}} ->
        Logger.debug("Busybody: registered #{payload.name} on port #{payload.port}")

      {:error, reason} ->
        Logger.warning("Busybody: registration failed: #{inspect(reason)}")

      other ->
        Logger.warning("Busybody: unexpected response: #{inspect(other)}")
    end
  end

  defp schedule_heartbeat(interval) do
    Process.send_after(self(), :heartbeat, interval)
  end
end
