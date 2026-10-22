# Busybody

## The Problem

When you're developing multiple Phoenix apps at once, you want them to
stay out of each other's way. The easiest trick is to let each app grab
a random port on startup — set `port: 0` in your dev config and the OS
picks one for you. No collisions, no coordination, no remembering which
app is on 4000 and which is on 4001.

But now you have a different problem: you don't know where anything is.
Each time an app starts it gets a new port. You have to watch the
startup log to catch it, and if you miss it — or you come back to your
desk after lunch — you're grepping through terminal history or running
`lsof` to find your own apps.

This is a solved problem in production. You run a service registry —
Consul, etcd, a load balancer — and services announce themselves. But
nobody sets up Consul for local dev. The overhead isn't worth it for
something that should be trivial.

## The Fix

Busybody is a small Phoenix app that acts as a service directory for
your local dev environment. It runs on a fixed, well-known port (5150)
and provides two things:

1. **A registration API.** Apps POST their name, port, host, and PID
   when they start up. They re-register every 60 seconds as a
   heartbeat.

2. **A live directory page.** A LiveView at `http://localhost:5150`
   that shows every registered app as a clickable card. Cards appear
   and disappear in real-time as apps come and go. No polling, no
   refreshing.

When an app dies without deregistering (which is most of the time —
Ctrl-C doesn't run shutdown hooks), a health checker runs every 30
seconds and TCP-probes each registered app. If it can't connect, the
entry gets pruned. Dead apps disappear from the directory within 30
seconds.

The whole thing is one Elixir app, no database, no external
dependencies. State lives in a GenServer. When busybody restarts,
it starts empty — and the client heartbeats refill it within 60
seconds.

## Architecture

There are five moving parts (four in this repo, plus the client):

**Registry** (`Busybody.Registry`) — A GenServer holding a map of
registered apps, keyed by name. Each entry carries the app's name,
port, PID, host, and timestamps. Changes are broadcast via PubSub so
the LiveView can react in real-time. Capped at 100 entries to prevent
abuse.

**Health Checker** (`Busybody.HealthChecker`) — A GenServer that fires
every 30 seconds, grabs the app list from the Registry, and
TCP-connects to each one. Failed connections trigger a deregister.
Probes run concurrently (up to 10 at a time) so a few slow hosts
can't stall the cycle.

**API Controller** (`BusybodyWeb.ApiController`) — Two endpoints:

    POST /api/register   {"name": "myapp", "port": 4829, "pid": "12345", "host": "devbox", "group": "infra"}
    GET  /api/apps        returns the full registry as JSON

Input is validated at the boundary: port must be an integer 1-65535,
name/pid/host must be non-empty strings. `group` is optional; when
present it must be a non-empty string.

**LiveView** (`BusybodyWeb.DirectoryLive`) — The directory page at `/`.
Subscribes to PubSub events from the Registry. Cards show the app
name, host, port, PID, and a relative "last seen" timestamp. Each card
links to the app. Status is encoded as glyph + word, never color alone:
`● OK` (seen in the last 60s), `◆ WARN` (stale), `✖ DOWN` (about to be
pruned). See `BusybodyWeb.Status`.

**Client** (`Busybody.Client`) — A GenServer that other Phoenix apps
add to their supervision tree. On startup it resolves the app's port
(from the endpoint config or an explicit option), registers with
busybody, and heartbeats every 60 seconds. It ships as its own
package, `busybody_client`, in the busybody-client repo — see
[Adding a Client App](#adding-a-client-app).

## Setup

Requires Elixir 1.20 and Erlang/OTP 29. `.tool-versions` pins both for
asdf. Start busybody:

    cd busybody
    mix setup
    mix phx.server

It binds to `0.0.0.0:5150` — reachable from other machines on the
network, not just localhost.

## Adding a Client App

The client is **not** this app. It is a separate, dependency-free
library, `busybody_client`, that lives in the
[busybody-client](https://github.com/imsmith/busybody-client) repo. Adding
this Phoenix app as a dependency would start a second registry and
endpoint inside your app and drag Phoenix, LiveView, and the asset
toolchain along with it. Add the client package instead.

Three changes. First, the endpoint, and this is the one that matters:
**the app must not pick its own port.** Busybody exists so that nobody
does. The default `phx.new` dev config binds a fixed port on loopback,
which is exactly the state busybody ends: a port you have to track, on
an address only this host can reach. In `config/runtime.exs`, let the
OS pick the port and listen on every interface:

    config :my_app, MyAppWeb.Endpoint,
      http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT", "0"))]

That is the only `http:` line in `config/`. Remove the ones `phx.new`
put in `config/dev.exs` and the prod block of `runtime.exs`; a second
`http:` anywhere silently wins. Never write `server: false` either: an
explicit `:server` key overrides `mix phx.server` and the endpoint never
binds. The client logs a warning at registration if it finds a fixed
port.

    grep -n 'http:\|server:' config/*.exs

Port `0` means a free port is assigned at bind time and changes on every
start. `{0, 0, 0, 0}` means the app answers on all IPv4 addresses, so
other machines, containers, and VMs on the network can reach it by
hostname, not just `localhost`. Busybody's health checker probes the
registered host and port from wherever busybody runs, so an app bound
to loopback on another machine would be pruned as dead.

Known gap: with `port: 0`, Phoenix url helpers still render `:0` until
the endpoint's `:url` config is synced to the bound port. See
`ISSUES.md`.

Then the dep, in `mix.exs`:

    {:busybody_client, github: "imsmith/busybody-client", only: :dev}

And the client, in `application.ex`, after your endpoint so the port is
bound before registration:

    children = [
      MyAppWeb.Endpoint,
      {Busybody.Client, name: "my_app", endpoint: MyAppWeb.Endpoint}
    ]

To group the app with others on the directory page, add `group` to the
same child spec. It is part of how the app presents itself, like
`name`, so it lives with `name` and not in `config/`:

    {Busybody.Client, name: "my_app", group: "infra", endpoint: MyAppWeb.Endpoint}

Omit it and the app is ungrouped. The group is sent with every
registration, so changing it takes effect on the next restart.

If that `application.ex` also boots in prod and test, where the dep is
absent, guard it:

    defp busybody_children do
      if Code.ensure_loaded?(Busybody.Client) do
        [{Busybody.Client, name: "my_app", endpoint: MyAppWeb.Endpoint}]
      else
        []
      end
    end

and append `++ busybody_children()` to the children list.

### Client Options

| Option | Default | Description |
|--------|---------|-------------|
| `name` | *(required)* | App name shown in the directory |
| `endpoint` | *(required unless `port` given)* | Phoenix endpoint module — used to resolve the port |
| `port` | *(from endpoint)* | Explicit port, overrides endpoint resolution |
| `registry_url` | `http://localhost:5150` | Where busybody is running |
| `host` | system hostname | Host shown in the directory and used for health checks |
| `group` | *(none)* | Optional group membership shown on the card |

## Non-Elixir apps

Busybody's API is language-neutral: any HTTP app can register by POSTing
its `name`, `port`, `pid`, and `host`, and re-POSTing every 60 seconds.

For the same "add one thing and it registers + heartbeats" experience the
Elixir client gives, use **[busybody-client](../busybody-client)** — a
process wrapper shipped as both a static Go binary and a POSIX-sh script:

    busybody run --name myapp -- ./my-server        # binary, auto-discovers the port
    busybody-run --name myapp --port 4000 -- ./run  # script, explicit port

It launches your app, discovers the listening port, registers, and
heartbeats — best-effort, so a downed busybody never affects your app.

### Raw HTTP

You don't need any client. Any HTTP tool works:

    curl -X POST http://localhost:5150/api/register \
      -H "Content-Type: application/json" \
      -d '{"name":"myapp","port":4000,"pid":"12345","host":"localhost"}'

Re-send it every 60 seconds to stay in the directory. A one-shot
registration works too — the entry just won't survive a busybody restart.

## Development

    mix precommit   # compile --warnings-as-errors, format, test (incl. doctests)
    mix dialyzer    # type check; first run builds the PLT (slow, cached after)

## License

AGPL-3.0
