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

There are five moving parts:

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
busybody, and heartbeats every 60 seconds.

## Setup

Requires Elixir 1.20 and Erlang/OTP 29. `.tool-versions` pins both for
asdf. Start busybody:

    cd busybody
    mix setup
    mix phx.server

It binds to `0.0.0.0:5150` — reachable from other machines on the
network, not just localhost.

## Adding a Client App

The fastest way is the install task. From inside your Phoenix project:

    mix busybody.install

This patches your `mix.exs` and `application.ex` in one shot. It adds
the dep, wires the client into your supervision tree, and gates it
behind `Code.ensure_loaded?/1` so it only runs when the dep is
available (i.e., dev). By default it infers the app name from your
OTP app and assumes busybody lives at `../busybody`.

Options:

    mix busybody.install --name my_cool_app
    mix busybody.install --path ../../tools/busybody
    mix busybody.install --git https://github.com/imsmith/busybody.git

After running the installer, just `mix deps.get` and start your app.

### What the installer does

The installer is an Igniter task — it patches your project's AST, so it is
robust to formatting and idempotent (safe to re-run). Because it is an Igniter
task, your project needs Igniter in its deps
(`{:igniter, "~> 0.8", only: [:dev, :test]}`) to run it. It makes two changes.
In `mix.exs`, it adds the dep:

    {:busybody, path: "../busybody", only: :dev}

In `application.ex`, it appends `++ busybody_children()` to your
children list and adds a helper function:

    defp busybody_children do
      if Code.ensure_loaded?(Busybody.Client) do
        [{Busybody.Client, name: "my_app", endpoint: MyAppWeb.Endpoint}]
      else
        []
      end
    end

The `Code.ensure_loaded?` guard means the app compiles and runs fine
in prod and test where busybody isn't a dependency. The client goes
after the endpoint in the children list so the port is bound before
registration happens.

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
