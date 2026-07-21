# Busybody — Language-Neutral Clients

**Date:** 2026-07-20
**Status:** Draft

## Overview

Busybody's server side is already language-neutral. The registration
contract is `POST /api/register {name, port, pid, host}` plus a re-POST
every 60 seconds, and health is TCP-probed on `host:port`. Nothing about
the registry, health checker, LiveView, or API is Elixir-specific — the
README already documents a raw-`curl` path under "Without the Client
Library."

What is missing is *ergonomics*. The Elixir `Busybody.Client` GenServer
resolves the app's port from the Phoenix endpoint config, discovers the
PID and hostname, registers on boot, and heartbeats — all from inside the
same BEAM VM. A non-Elixir HTTP app has none of that; today it must
hand-roll a curl-in-a-loop.

This spec adds two standalone client artifacts that give any non-Elixir
**HTTP web app** the same "add one thing and it registers + heartbeats"
experience, without touching the server.

## Scope

- **In scope:** HTTP web apps in any language that listen on a TCP port
  (Go, Python, Ruby, Rust, etc.). Same shape as the Phoenix apps today;
  the clickable `http://host:port` card and TCP health-probe work as-is.
- **Out of scope:** non-HTTP TCP services, portless processes/scripts,
  and one-shot CLI tools. See "Out of Scope" below.

## What Does Not Change

The Elixir server, registry, health checker, LiveView, API controller,
and `Busybody.Client` are all untouched.

Deregistration continues to rely on health-check pruning. When a wrapped
app dies, its port frees, the next 30-second health check fails to TCP-
connect, and the entry is pruned. **The new clients therefore need no
deregister call** — consistent with the existing design decision that
there is no `DELETE` endpoint.

## Shared CLI Contract

Both artifacts implement the identical flag contract, wrapper-style. The
client launches the app as a child process, registers it, heartbeats,
and shares its lifecycle.

```text
busybody-run --name NAME [--port PORT] [--host HOST] [--registry-url URL] -- CMD [ARGS...]
```

| Flag | Required | Default | Meaning |
|------|----------|---------|---------|
| `--name` | yes | — | App name shown in the directory |
| `--port` | no | *(auto-discover)* | Explicit port; skips discovery |
| `--host` | no | system hostname | Host shown in directory and used for health checks |
| `--registry-url` | no | `http://localhost:5150` | Where busybody is running |
| `--` | yes | — | Separator; everything after is the child command |

Behavior:

1. Spawn `CMD [ARGS...]` as a child process.
2. Determine the port (explicit `--port`, else auto-discover — see below).
3. `POST /api/register` with `{name, port, pid, host}`, where `pid` is the
   **child's** OS PID.
4. Heartbeat: re-POST every 60 seconds.
5. Forward `SIGTERM` and `SIGINT` to the child.
6. When the child exits, exit with the child's exit code.

The 60-second heartbeat matches the Elixir client and the server's
timing model (health check at 30s, staleness/amber at 90s).

## The Two Artifacts

Both implement the contract above; only the packaging differs.

### `clients/sh/busybody-run` — POSIX-sh sidecar

For the host dev box. Zero build step; drop it into a Makefile or
Procfile.

- Dependencies: `curl` and `ss` (iproute2), both present on Debian and
  Alpine.
- Single self-contained script.

### `clients/go/` — `busybody` static binary

For containers (Alpine) and anywhere an interpreter is unwanted.

- Single static binary, no runtime dependencies.
- Invoked as a subcommand: `busybody run -- CMD` (same flags as the
  script). The subcommand form leaves room to grow.
- Built with `go build`; shipped as a release artifact.

## Port Auto-Discovery

When `--port` is omitted, the wrapper discovers the child's listening
port. After spawning the child, it polls approximately every 200ms, up
to a ~10-second timeout, for a `LISTEN` socket owned by the child PID.

- **Script:** `ss -Htlnp`, match the row whose `users:((...pid=<child>...))`
  field names the child PID, and take that port.
- **Go binary:** parse `/proc/net/tcp` and `/proc/net/tcp6` for sockets in
  state `0A` (LISTEN), then cross-reference each socket inode against the
  entries in `/proc/<child>/fd`. This keeps the container binary free of
  external dependencies (no reliance on `ss` being installed).

The first listening port found wins. If an app binds several ports, the
user passes `--port` to disambiguate.

## Lifecycle & Error Handling

A dev tool must never take down the app it wraps. All registry
interactions are best-effort:

- **Registry unreachable at startup or on a heartbeat:** log a warning,
  keep the child running, retry on the next 60-second tick. Never fatal.
- **Port not found before the discovery timeout (and no `--port`):** keep
  the child running, keep retrying discovery, and register once a
  listening port appears.
- **Child exits:** the wrapper exits with the same exit code. The stale
  registry entry is pruned by the server's health check within 30
  seconds.

## Testing

### Go binary

- Unit-test `/proc`-based port discovery against a real listener opened
  inside the test.
- Integration-test the wrapper against a stub HTTP registry: assert the
  initial register POST fires with the right fields, assert a repeated
  heartbeat POST, and assert the wrapper propagates the child's exit
  code.

### Script

- Smoke test: run `busybody-run` wrapping a small listener child (e.g.
  `nc`) against a stub registry, and assert a register POST fires.

## File Layout

The clients live in their own repository, `~/github/busybody-client`
(currently an empty directory, not yet a git repo). Keeping them out of
the Elixir `busybody` repo avoids mixing a Go/shell toolchain into a
Phoenix project and lets the clients version and release independently.

```text
busybody-client/           # standalone git repo
  README.md
  LICENSE                  # AGPL-3.0
  Makefile                 # build the Go binary
  sh/
    busybody-run
  go/
    go.mod
    main.go
    run.go
    discover_linux.go
    *_test.go
```

## Documentation

`busybody-client` gets its own `README.md` documenting the wrapper usage
for both artifacts, with language-neutral examples (e.g. `-- ./myserver`,
`-- python -m http.server`), not JavaScript-ecosystem examples.

The main `busybody` repo's README gains a short "Non-Elixir apps" pointer
that expands today's "Without the Client Library" content and links to
the `busybody-client` repo.

## Out of Scope (YAGNI)

- Registering non-HTTP TCP services or portless processes/scripts.
- A one-shot `register` subcommand (background sidecar mode).
- A `list` subcommand wrapping `GET /api/apps`.
- macOS/BSD port discovery — Linux-first (`/proc`, `ss`), matching the
  Debian/Alpine target.
- Per-language client libraries and published packages (npm, pip, Go
  module).
- Any server-side change.
