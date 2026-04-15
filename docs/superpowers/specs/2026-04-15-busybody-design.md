# Busybody — Phoenix Dev App Directory

**Date:** 2026-04-15
**Status:** Draft

## Overview

A Phoenix LiveView app that acts as a service registry for local Phoenix development. Apps register themselves on startup, and busybody provides a live-updating directory page so you can always find what's running and where.

## Architecture

Single Phoenix app, single repo. Two logical halves:

1. **Registry** — a GenServer holding an in-memory map of registered apps. No database. Everything evaporates on restart; apps re-register via heartbeat.
2. **Client** — `Busybody.Client`, a GenServer that consumer apps add to their supervision tree. POSTs registration on boot and heartbeats every 60 seconds.

Consumer apps add busybody as a path or git dependency, gated to dev only.

## Network

- Registry binds to `0.0.0.0:5150`.
- Client defaults to `localhost:5150`, configurable via `registry_url` option.
- Directory page links use the registering app's hostname, not hardcoded localhost.

## Data Model

In-memory map in the registry GenServer, keyed by app name:

```elixir
%{
  "paperclip" => %{
    name: "paperclip",
    port: 4829,
    pid: "12345",
    host: "ian-dev",
    registered_at: ~U[2026-04-15 14:30:00Z],
    last_seen: ~U[2026-04-15 14:35:00Z]
  }
}
```

No persistence. Registry restart = clean slate, repopulated within 60 seconds by client heartbeats.

## API

### POST /api/register

Accepts JSON:

```json
{
  "name": "paperclip",
  "port": 4829,
  "pid": "12345",
  "host": "ian-dev"
}
```

Upserts the entry in the registry, updates `last_seen`, broadcasts change via PubSub. Returns 200.

### GET /api/apps

Returns the full registry as JSON. For debugging and scripting.

No DELETE endpoint. Deregistration is handled by health check pruning.

## Health Check & Heartbeat

### Registry-side health checker

- Runs every 30 seconds.
- TCP connects to `{host}:{port}` for each registered app with a 2-second timeout.
- Failed connections prune the entry and broadcast removal via PubSub.
- Net effect: dead apps disappear within 30 seconds.

### Client-side heartbeat

- Re-POSTs registration every 60 seconds.
- Covers registry restarts — apps re-register without intervention.
- Keeps `last_seen` fresh.
- Net effect: restarted registry repopulates within 60 seconds.

## LiveView Directory Page

Single page at `/`.

### Layout

Card-based grid. Each registered app is a card showing:

- App name (clickable link to `http://{host}:{port}`, opens in new tab)
- Port
- PID
- Relative `last_seen` time (e.g., "3s ago")

Header with "busybody" branding and count of live apps. Responsive grid — works for 2 apps or 20.

### Status Indicators

- **Green dot:** healthy (heartbeat within last 60 seconds)
- **Amber dot:** stale (no heartbeat in >90 seconds, not yet pruned)
- Entry fades out and disappears on prune.

### Styling

Tailwind CSS (ships with Phoenix). Two color modes via `prefers-color-scheme`:

- **Light mode:** Tufte warm ivory/cream background (`#fffff8`), dark sepia-toned text, warm-bordered cards.
- **Dark mode:** conventional dark neutrals, lighter cards, adjusted contrast.

No manual toggle — follows system preference.

## Client Module

`Busybody.Client` — a GenServer for consumer apps.

### Usage

Consumer apps add busybody as a dependency:

```elixir
# mix.exs
{:busybody, path: "../busybody", only: :dev}
```

Add to supervision tree (dev only):

```elixir
children = [
  MyAppWeb.Endpoint,
  {Busybody.Client, name: "my_app", endpoint: MyAppWeb.Endpoint}
]
```

### Configuration Options

- `name` — app name to register (required)
- `endpoint` — the Phoenix endpoint module, used to resolve the port (required)
- `registry_url` — defaults to `"http://localhost:5150"`, override for remote registries
- `host` — defaults to machine hostname, override if needed

### Behavior

1. On start, waits briefly for the endpoint to bind.
2. Resolves port from the endpoint config.
3. POSTs registration to the registry.
4. Starts 60-second heartbeat timer.
5. Re-registers on each heartbeat tick.

## Project Structure

Standard Phoenix app generated with `mix phx.new busybody --no-ecto --no-mailer --no-dashboard`.

No database. No mailer. No LiveDashboard (it *is* the dashboard).

## Out of Scope

- Authentication / authorization (dev tool, trusted network)
- Persistent storage
- Multi-node clustering
- App control (start/stop/restart from the directory)
