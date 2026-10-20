defmodule Busybody do
  @moduledoc """
  Busybody is a service directory for local Phoenix development.

  Apps that bind a random port register here (`POST /api/register`) and
  heartbeat every 60 seconds; the directory page at `/` lists them live.

  Core processes:

    * `Busybody.Registry` — in-memory map of registered apps, broadcast over PubSub
    * `Busybody.HealthChecker` — TCP-probes each entry every 30s and prunes the unreachable
    * `Busybody.Client` — the consumer-side GenServer, shipped separately as the `busybody_client` package in the busybody-client repo

  The web layer lives under `BusybodyWeb`.
  """
end
