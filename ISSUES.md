# Issues

Tracked here until they migrate to a real issue tracker. Newest first.

## Directory should section cards by `group`

**Filed:** 2026-10-15
**Status:** deferred, wanted

Registrations now carry an optional `group` string. The directory shows
it as a row on the card only. The intended end state is a grid
sectioned by group (ungrouped apps in their own section). `group`
values are currently any non-empty string; input validation on the
value is also planned and should land before or with the sectioning.

## Adding busybody as a dep boots the whole server inside the client app

**Filed:** 2026-10-14
**Reported from:** installing the client into paperclip

### Symptom

The model is one busybody server per dev box and a thin client in every app.
The dep the installer adds does not deliver that. `mix.exs` declares
`mod: {Busybody.Application, []}`, so any project that lists `:busybody`
starts `Busybody.Registry`, `Busybody.HealthChecker`, `BusybodyWeb.Telemetry`,
a second `Phoenix.PubSub`, and `BusybodyWeb.Endpoint` inside its own VM.
First symptom in the client app's log:

```text
[warning] no configuration found for otp_app :busybody and module BusybodyWeb.Endpoint
[info] Access BusybodyWeb.Endpoint at http://localhost
```

Under `mix phx.server` the host sets `:serve_endpoints` for every endpoint in
the VM, so the embedded `BusybodyWeb.Endpoint` will also try to bind if it ever
gets a port. Each client app runs its own empty registry and a health checker
that probes nothing every 30 seconds. The client itself needs only
`Jason` and `:inets` (`:httpc`).

### Why it happens

Server and client share one OTP application. The installer adds the dep as
`{:busybody, path: ..., only: :dev}` with the application started by default.

### What should change

Shortest fix, no restructuring: have the installer add the dep with
`runtime: false` and add `:inets` to the host's `extra_applications`. The
`Busybody.Client` module stays on the code path, nothing from the server
starts, and the existing `Code.ensure_loaded?` guard still works. Verified
in paperclip: registration succeeds, no busybody processes in the host VM.
Document the same two lines in the README for manual installs.

Longer term, the client is a candidate for its own package (an Elixir
`busybody_client` next to the Go and sh ones in `busybody-client`) so the
dep carries no Phoenix at all.

---

## `pid` is accepted empty, contradicting the README's validation claim

**Filed:** 2026-08-04
**Reported from:** as-built architecture review

### Symptom

`README.md:70` states the contract:

```text
name/pid/host must be non-empty strings.
```

`lib/busybody_web/controllers/api_controller.ex:11-14` implements
something narrower:

```elixir
  def register(conn, %{"name" => name, "port" => port, "pid" => pid, "host" => host})
      when is_binary(name) and byte_size(name) > 0
      and is_integer(port) and port in 1..65_535
      and is_binary(pid) and is_binary(host) and byte_size(host) > 0 do
```

`name` and `host` carry `byte_size(...) > 0`. `pid` carries only
`is_binary(pid)`. A registration with `"pid": ""` passes the guard and
lands in the registry, and the 422 fallback clause's own error message
("pid (string)") is what the caller would have to reverse-engineer the
real rule from.

### Why it happens

The `byte_size/1` check was applied to two of the three string fields.
Nothing in the guard chain covers `pid`.

### What should change

Either add `and byte_size(pid) > 0` to the guard so the code matches
the README, or amend the README to say `pid` may be empty and say what
an empty `pid` means to a consumer of `GET /api/apps`. The first is
almost certainly what was meant — the directory card renders the PID,
and an empty one is not useful to anybody.

---

## `BusybodyWeb.Status`'s moduledoc claims a prune window that does not exist

**Filed:** 2026-08-04
**Reported from:** as-built architecture review

### Symptom

`lib/busybody_web/status.ex:6-7`:

```elixir
  accessibility invariant). Thresholds match the health checker's prune window:
  healthy `< 60s`, stale `< 90s`, dying `>= 90s`.
```

There is no `last_seen`-based prune window to match. `Busybody.HealthChecker`
prunes on one condition only — a failed TCP connect
(`lib/busybody/health_checker.ex:41-50`):

```elixir
    |> Enum.each(fn
      {:ok, {name, :unreachable}} ->
        Busybody.Registry.deregister(registry, name)
```

`last_seen` appears nowhere in the health checker. The 60s/90s
thresholds in `Status.classify/2` are a pure display concern with no
relationship to pruning.

The README carries the same wrong implication at line 76: status dots
described as "red (about to be pruned)".

### Why it happens

Two independent staleness notions were conflated. The health checker
answers "is something listening on this port?"; `Status` answers "how
long since this app last heartbeated?". They can disagree.

The concrete failure case: an app whose `Busybody.Client` GenServer has
died while the app itself is still listening. TCP probes keep
succeeding, so it is never pruned; heartbeats have stopped, so
`last_seen` ages without bound. The card sits at DOWN indefinitely — the
one state the docs say is transient.

### What should change

Fix the docs at minimum: `Status`'s thresholds are a display convention,
not a prune schedule, and a DOWN card is not necessarily about to
disappear.

Whether the behavior should also change is a design decision. Adding a
`last_seen` age to the prune condition would make the docs true and
would clear stuck-DOWN entries, but it also means an app that is up and
serving gets removed from the directory because its heartbeat client
crashed. Decide which failure you would rather have before writing code.

---

## `Busybody.Registry.deregister/2` is unreachable from outside the node

**Filed:** 2026-08-04
**Reported from:** as-built architecture review

### Symptom

`lib/busybody/registry.ex:57` is a public, doctested API function:

```elixir
  def deregister(server \\ __MODULE__, name) do
```

`lib/busybody_web/router.ex:25-29` exposes two routes and no more:

```elixir
    post "/register", ApiController, :register
    get "/apps", ApiController, :index
```

No HTTP path reaches `deregister/2`. Its only production caller is
`Busybody.HealthChecker.check_all/1` at
`lib/busybody/health_checker.ex:43`; every other reference is a test.
A well-behaved client that wants to remove itself cleanly on shutdown
has no way to say so — it can only stop listening and wait up to 30
seconds to be pruned.

### Why it happens

This is deliberate, and the README says why at lines 37-40: apps mostly
die without deregistering because Ctrl-C does not run shutdown hooks,
so TCP probing was chosen as the mechanism that works regardless.

### What should change

Probably nothing. This is recorded as an inventory fact, not a defect:
`deregister/2` is an internal capability with a public function
signature and doctests, which reads to a newcomer as part of the API
surface. If it is to stay internal, a `@doc false` or a moduledoc note
saying "callers outside the node use the health checker" would stop the
next person from looking for the missing route. If a graceful-shutdown
path is ever wanted, note that adding `DELETE /api/register/:name`
means adding an authorization question this app currently does not have
— today anyone who can reach the port can register, and deregistration
would let them evict others.

---

## Verified accurate: the `busybody.install` "inert stub" moduledoc

**Filed:** 2026-08-04
**Reported from:** as-built architecture review

### Symptom

None. Recorded so nobody files this as documentation drift.

`lib/mix/tasks/busybody.install.ex:19-21` claims:

```text
    Requires [Igniter](https://hexdocs.pm/igniter) in the host project's deps
    (`{:igniter, "~> 0.8", only: [:dev, :test]}`). Without it, this task is an
    inert stub that prints an install hint.
```

The file is wrapped in `if Code.ensure_loaded?(Igniter) do ... else ... end`,
and the `else` branch does exactly that — it defines a real
`Mix.Task` whose `run/1` prints an install hint via `Mix.shell().error/1`
and then `exit({:shutdown, 1})`.

The claim holds. The only nuance worth knowing is that "inert" still
means a nonzero exit status, so a CI step invoking `mix busybody.install`
without Igniter fails rather than silently no-ops. That is the right
behavior; it is just not what "inert" suggests on first read.

---

## `busybody.install` should sync the endpoint's `:url` port to the bound port

**Filed:** 2026-05-11
**Reported from:** bookweb integration

### Symptom

When a consuming Phoenix app sets `port: 0` (OS-assigned) in its dev
`http:` config, Phoenix's url helpers still emit URLs with `:0` in
them — `http://localhost:0/...`. This breaks anything that renders a
URL outside of a live request: most importantly, the magic-link
emails generated by `phx.gen.auth`-style notifiers. Browsers also
refuse to connect to `:0` outright (Firefox treats it as a restricted
port).

The bound port *is* discoverable at runtime — busybody itself reads
it via `Endpoint.server_info(:http)` for registration. The same call
can populate the endpoint's `:url` config so url helpers produce
links that match where the server is listening.

### What `busybody.install` should add

Append a helper to the consumer's `Application.start/2` that runs
after `Supervisor.start_link`, alongside the existing
`busybody_children/0` patch. Something like:

```elixir
defp sync_endpoint_url_port do
  case ConsumerWeb.Endpoint.config(:http) do
    [_ | _] = http ->
      if Keyword.get(http, :port) == 0, do: rewrite_url_port()

    _ ->
      :ok
  end
end

defp rewrite_url_port do
  with {:ok, {_addr, port}} <- ConsumerWeb.Endpoint.server_info(:http) do
    config = Application.get_env(:consumer, ConsumerWeb.Endpoint, [])
    new_url = config |> Keyword.get(:url, []) |> Keyword.put(:port, port)
    new_config = Keyword.put(config, :url, new_url)

    Application.put_env(:consumer, ConsumerWeb.Endpoint, new_config)
    ConsumerWeb.Endpoint.config_change([{ConsumerWeb.Endpoint, new_config}], [])
  end
end
```

And invoke `sync_endpoint_url_port()` after `Supervisor.start_link`
returns in `start/2`.

### Gotchas worth encoding in the installer

1. `Endpoint.config_change/2` expects `changed` to be a keyword list
   `[{EndpointModule, full_config_kwlist}]` — *not* a map of
   individual changed keys. Passing the partial-map shape silently
   no-ops via the `clear_cache/1` fallback in `Phoenix.Config`, which
   makes this easy to get wrong.
2. The sync must run only when `http[:port] == 0`; running it
   unconditionally would overwrite a deliberately-pinned `url[:port]`
   (e.g. someone running behind a reverse proxy where the public
   port differs from the bound port).
3. `Endpoint.server_info(:http)` returns `{:error, :no_server_found}`
   when started without `server: true` (e.g. plain `mix run` rather
   than `mix phx.server`). The `with` clause should fall through
   silently in that case — there's no http server, so url-helper
   accuracy isn't load-bearing.

### Current workaround

Implemented locally in `bookweb/lib/bookweb/application.ex` as
`sync_endpoint_url_port/0` + `rewrite_url_port/0`. Lift that code
verbatim (plus AST templating for the consumer's module name and OTP
app) into the install task.

### Why it belongs in busybody

The whole reason a consumer is opting into `port: 0` is the workflow
busybody enables — multiple Phoenix apps on the same machine without
port-collision bookkeeping. busybody already discovers the bound
port for its own registration; it's the natural place to also push
that port back into the consumer's url config. Without this, every
busybody consumer hits the broken-email-link footgun and has to
reproduce the same shim.
