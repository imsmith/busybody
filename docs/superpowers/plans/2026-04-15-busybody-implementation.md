# Busybody Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Phoenix LiveView app that acts as a dev service registry — apps register on startup, busybody shows a live directory of everything running.

**Architecture:** Single Phoenix app on port 5150. Registry GenServer holds in-memory map of apps. Health checker prunes dead entries via TCP. Client GenServer for consumer apps handles registration and heartbeat. LiveView page with PubSub for real-time updates.

**Tech Stack:** Elixir 1.19, Phoenix 1.8, LiveView, Tailwind CSS, Bandit

**Spec:** `docs/superpowers/specs/2026-04-15-busybody-design.md`

---

## File Structure

```
busybody/
├── lib/
│   ├── busybody/
│   │   ├── application.ex          # Supervision tree
│   │   ├── registry.ex             # GenServer — app registry state
│   │   ├── health_checker.ex       # Periodic TCP health checks
│   │   └── client.ex               # Client GenServer for consumer apps
│   └── busybody_web/
│       ├── endpoint.ex             # Phoenix endpoint
│       ├── router.ex               # Routes
│       ├── controllers/
│       │   └── api_controller.ex   # POST /api/register, GET /api/apps
│       └── live/
│           └── directory_live.ex   # LiveView directory page
├── test/
│   ├── busybody/
│   │   ├── registry_test.exs       # Registry GenServer tests
│   │   ├── health_checker_test.exs # Health checker tests
│   │   └── client_test.exs         # Client module tests
│   └── busybody_web/
│       ├── controllers/
│       │   └── api_controller_test.exs
│       └── live/
│           └── directory_live_test.exs
├── config/
│   ├── config.exs
│   ├── dev.exs
│   ├── test.exs
│   ├── prod.exs
│   └── runtime.exs
└── mix.exs
```

---

### Task 1: Scaffold Phoenix App

**Files:**
- Create: entire project scaffold via `mix phx.new`
- Modify: `config/dev.exs` (port 5150, bind 0.0.0.0)
- Modify: `config/config.exs` (remove mailer config if generated)

- [ ] **Step 1: Generate the Phoenix project**

Run from `~/github`:

```bash
cd ~/github && mix phx.new busybody --no-ecto --no-mailer --no-dashboard --app busybody
```

When prompted to install deps, say yes.

- [ ] **Step 2: Configure port 5150 and bind 0.0.0.0 in dev.exs**

In `config/dev.exs`, find the http config line and change it to:

```elixir
config :busybody, BusybodyWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 5150],
```

- [ ] **Step 3: Configure test to use a random port**

In `config/test.exs`, ensure the endpoint uses a random port (should be default, verify):

```elixir
config :busybody, BusybodyWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 0],
```

- [ ] **Step 4: Verify it compiles and starts**

```bash
cd ~/github/busybody && mix compile && mix phx.server
```

Expected: server starts on port 5150, default Phoenix landing page loads at `http://localhost:5150`.

Kill the server after verifying.

- [ ] **Step 5: Run existing tests**

```bash
cd ~/github/busybody && mix test
```

Expected: default generated tests pass.

- [ ] **Step 6: Commit**

```bash
cd ~/github/busybody && git init && git add -A && git commit -m "scaffold: phoenix app with port 5150"
```

---

### Task 2: Registry GenServer

**Files:**
- Create: `lib/busybody/registry.ex`
- Test: `test/busybody/registry_test.exs`

- [ ] **Step 1: Write the failing tests**

Create `test/busybody/registry_test.exs`:

```elixir
defmodule Busybody.RegistryTest do
  use ExUnit.Case, async: true

  alias Busybody.Registry

  setup do
    registry = start_supervised!({Registry, name: :"registry_#{System.unique_integer()}"})
    %{registry: registry}
  end

  describe "register/2" do
    test "registers an app", %{registry: registry} do
      attrs = %{name: "myapp", port: 4000, pid: "12345", host: "localhost"}
      assert :ok = Registry.register(registry, attrs)
      assert [app] = Registry.list(registry)
      assert app.name == "myapp"
      assert app.port == 4000
      assert app.pid == "12345"
      assert app.host == "localhost"
      assert %DateTime{} = app.registered_at
      assert %DateTime{} = app.last_seen
    end

    test "upserts on duplicate name", %{registry: registry} do
      attrs = %{name: "myapp", port: 4000, pid: "12345", host: "localhost"}
      Registry.register(registry, attrs)

      updated = %{name: "myapp", port: 4001, pid: "12346", host: "localhost"}
      Registry.register(registry, updated)

      assert [app] = Registry.list(registry)
      assert app.port == 4001
      assert app.pid == "12346"
    end

    test "multiple apps coexist", %{registry: registry} do
      Registry.register(registry, %{name: "app1", port: 4000, pid: "1", host: "localhost"})
      Registry.register(registry, %{name: "app2", port: 4001, pid: "2", host: "localhost"})

      apps = Registry.list(registry)
      assert length(apps) == 2
      names = Enum.map(apps, & &1.name) |> Enum.sort()
      assert names == ["app1", "app2"]
    end
  end

  describe "deregister/2" do
    test "removes an app by name", %{registry: registry} do
      Registry.register(registry, %{name: "myapp", port: 4000, pid: "1", host: "localhost"})
      assert :ok = Registry.deregister(registry, "myapp")
      assert [] = Registry.list(registry)
    end

    test "no-op for unknown name", %{registry: registry} do
      assert :ok = Registry.deregister(registry, "unknown")
    end
  end

  describe "list/1" do
    test "returns empty list when no apps registered", %{registry: registry} do
      assert [] = Registry.list(registry)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd ~/github/busybody && mix test test/busybody/registry_test.exs
```

Expected: compilation error — `Busybody.Registry` module not found.

- [ ] **Step 3: Implement the Registry GenServer**

Create `lib/busybody/registry.ex`:

```elixir
defmodule Busybody.Registry do
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd ~/github/busybody && mix test test/busybody/registry_test.exs
```

Expected: all 6 tests pass.

- [ ] **Step 5: Commit**

```bash
cd ~/github/busybody && git add lib/busybody/registry.ex test/busybody/registry_test.exs && git commit -m "feat: registry genserver with register/deregister/list"
```

---

### Task 3: Health Checker

**Files:**
- Create: `lib/busybody/health_checker.ex`
- Test: `test/busybody/health_checker_test.exs`

- [ ] **Step 1: Write the failing tests**

Create `test/busybody/health_checker_test.exs`:

```elixir
defmodule Busybody.HealthCheckerTest do
  use ExUnit.Case, async: true

  alias Busybody.Registry
  alias Busybody.HealthChecker

  setup do
    registry = start_supervised!({Registry, name: :"registry_#{System.unique_integer()}"})
    %{registry: registry}
  end

  describe "check_all/1" do
    test "prunes apps with unreachable ports", %{registry: registry} do
      # Register an app on a port nothing is listening on
      Registry.register(registry, %{
        name: "dead_app",
        port: 59999,
        pid: "1",
        host: "127.0.0.1"
      })

      assert [_] = Registry.list(registry)

      HealthChecker.check_all(registry)

      assert [] = Registry.list(registry)
    end

    test "keeps apps with reachable ports", %{registry: registry} do
      # Start a TCP listener
      {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(listen)

      Registry.register(registry, %{
        name: "live_app",
        port: port,
        pid: "1",
        host: "127.0.0.1"
      })

      HealthChecker.check_all(registry)

      assert [app] = Registry.list(registry)
      assert app.name == "live_app"

      :gen_tcp.close(listen)
    end

    test "prunes only dead apps from a mix", %{registry: registry} do
      {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(listen)

      Registry.register(registry, %{name: "alive", port: port, pid: "1", host: "127.0.0.1"})
      Registry.register(registry, %{name: "dead", port: 59998, pid: "2", host: "127.0.0.1"})

      HealthChecker.check_all(registry)

      apps = Registry.list(registry)
      assert length(apps) == 1
      assert hd(apps).name == "alive"

      :gen_tcp.close(listen)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd ~/github/busybody && mix test test/busybody/health_checker_test.exs
```

Expected: compilation error — `Busybody.HealthChecker` not found.

- [ ] **Step 3: Implement the HealthChecker**

Create `lib/busybody/health_checker.ex`:

```elixir
defmodule Busybody.HealthChecker do
  use GenServer

  @default_interval :timer.seconds(30)
  @tcp_timeout :timer.seconds(2)

  def start_link(opts) do
    interval = Keyword.get(opts, :interval, @default_interval)
    registry = Keyword.get(opts, :registry, Busybody.Registry)
    GenServer.start_link(__MODULE__, %{interval: interval, registry: registry}, name: __MODULE__)
  end

  def check_all(registry \\ Busybody.Registry) do
    apps = Busybody.Registry.list(registry)

    Enum.each(apps, fn app ->
      host = to_charlist(app.host)

      case :gen_tcp.connect(host, app.port, [], @tcp_timeout) do
        {:ok, socket} ->
          :gen_tcp.close(socket)

        {:error, _} ->
          Busybody.Registry.deregister(registry, app.name)
      end
    end)
  end

  @impl true
  def init(state) do
    schedule_check(state.interval)
    {:ok, state}
  end

  @impl true
  def handle_info(:check, state) do
    check_all(state.registry)
    schedule_check(state.interval)
    {:noreply, state}
  end

  defp schedule_check(interval) do
    Process.send_after(self(), :check, interval)
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd ~/github/busybody && mix test test/busybody/health_checker_test.exs
```

Expected: all 3 tests pass.

- [ ] **Step 5: Commit**

```bash
cd ~/github/busybody && git add lib/busybody/health_checker.ex test/busybody/health_checker_test.exs && git commit -m "feat: health checker prunes unreachable apps via TCP"
```

---

### Task 4: API Controller

**Files:**
- Create: `lib/busybody_web/controllers/api_controller.ex`
- Modify: `lib/busybody_web/router.ex`
- Test: `test/busybody_web/controllers/api_controller_test.exs`

- [ ] **Step 1: Write the failing tests**

Create `test/busybody_web/controllers/api_controller_test.exs`:

```elixir
defmodule BusybodyWeb.ApiControllerTest do
  use BusybodyWeb.ConnCase

  setup do
    # Clear registry between tests
    apps = Busybody.Registry.list()
    Enum.each(apps, fn app -> Busybody.Registry.deregister(app.name) end)
    :ok
  end

  describe "POST /api/register" do
    test "registers an app", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/register", %{
          "name" => "testapp",
          "port" => 4000,
          "pid" => "12345",
          "host" => "devbox"
        })

      assert json_response(conn, 200) == %{"status" => "ok"}

      apps = Busybody.Registry.list()
      assert length(apps) == 1
      assert hd(apps).name == "testapp"
      assert hd(apps).host == "devbox"
    end

    test "returns 422 when name is missing", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/register", %{"port" => 4000, "pid" => "1", "host" => "x"})

      assert json_response(conn, 422)
    end
  end

  describe "GET /api/apps" do
    test "returns empty list when nothing registered", %{conn: conn} do
      conn = get(conn, "/api/apps")
      assert json_response(conn, 200) == %{"apps" => []}
    end

    test "returns registered apps", %{conn: conn} do
      Busybody.Registry.register(%{name: "app1", port: 4000, pid: "1", host: "localhost"})

      conn = get(conn, "/api/apps")
      %{"apps" => [app]} = json_response(conn, 200)
      assert app["name"] == "app1"
      assert app["port"] == 4000
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd ~/github/busybody && mix test test/busybody_web/controllers/api_controller_test.exs
```

Expected: compilation error — controller module not found, route not defined.

- [ ] **Step 3: Add the routes**

In `lib/busybody_web/router.ex`, add an API scope. Find the existing router and add:

```elixir
  scope "/api", BusybodyWeb do
    pipe_through :api

    post "/register", ApiController, :register
    get "/apps", ApiController, :index
  end
```

The `:api` pipeline should already exist in the generated router.

- [ ] **Step 4: Implement the controller**

Create `lib/busybody_web/controllers/api_controller.ex`:

```elixir
defmodule BusybodyWeb.ApiController do
  use BusybodyWeb, :controller

  def register(conn, %{"name" => name, "port" => port, "pid" => pid, "host" => host}) do
    Busybody.Registry.register(%{
      name: name,
      port: port,
      pid: pid,
      host: host
    })

    json(conn, %{status: "ok"})
  end

  def register(conn, _params) do
    conn
    |> put_status(422)
    |> json(%{error: "missing required fields: name, port, pid, host"})
  end

  def index(conn, _params) do
    apps =
      Busybody.Registry.list()
      |> Enum.map(fn app ->
        %{
          name: app.name,
          port: app.port,
          pid: app.pid,
          host: app.host,
          registered_at: DateTime.to_iso8601(app.registered_at),
          last_seen: DateTime.to_iso8601(app.last_seen)
        }
      end)

    json(conn, %{apps: apps})
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd ~/github/busybody && mix test test/busybody_web/controllers/api_controller_test.exs
```

Expected: all 4 tests pass.

- [ ] **Step 6: Commit**

```bash
cd ~/github/busybody && git add lib/busybody_web/controllers/api_controller.ex lib/busybody_web/router.ex test/busybody_web/controllers/api_controller_test.exs && git commit -m "feat: API endpoints for register and list apps"
```

---

### Task 5: Wire Up Supervision Tree

**Files:**
- Modify: `lib/busybody/application.ex`

- [ ] **Step 1: Add Registry and HealthChecker to the supervision tree**

In `lib/busybody/application.ex`, add `Busybody.Registry` and `Busybody.HealthChecker` to the children list, before the Endpoint:

```elixir
children = [
  BusybodyWeb.Telemetry,
  {Phoenix.PubSub, name: Busybody.PubSub},
  Busybody.Registry,
  Busybody.HealthChecker,
  BusybodyWeb.Endpoint
]
```

- [ ] **Step 2: Verify the app starts and API works**

```bash
cd ~/github/busybody && mix phx.server &
sleep 3
curl -s -X POST http://localhost:5150/api/register \
  -H "Content-Type: application/json" \
  -d '{"name":"test","port":5150,"pid":"1","host":"localhost"}'
curl -s http://localhost:5150/api/apps | python3 -m json.tool
kill %1
```

Expected: POST returns `{"status":"ok"}`, GET returns the registered app.

- [ ] **Step 3: Run full test suite**

```bash
cd ~/github/busybody && mix test
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
cd ~/github/busybody && git add lib/busybody/application.ex && git commit -m "feat: wire registry and health checker into supervision tree"
```

---

### Task 6: LiveView Directory Page

**Files:**
- Create: `lib/busybody_web/live/directory_live.ex`
- Modify: `lib/busybody_web/router.ex`
- Test: `test/busybody_web/live/directory_live_test.exs`

- [ ] **Step 1: Write the failing tests**

Create `test/busybody_web/live/directory_live_test.exs`:

```elixir
defmodule BusybodyWeb.DirectoryLiveTest do
  use BusybodyWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup do
    apps = Busybody.Registry.list()
    Enum.each(apps, fn app -> Busybody.Registry.deregister(app.name) end)
    :ok
  end

  test "renders empty state", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")
    assert html =~ "busybody"
    assert html =~ "0"
  end

  test "shows registered apps", %{conn: conn} do
    Busybody.Registry.register(%{name: "paperclip", port: 4829, pid: "100", host: "devbox"})

    {:ok, view, html} = live(conn, "/")
    assert html =~ "paperclip"
    assert html =~ "4829"
    assert html =~ "devbox"
  end

  test "updates in real-time when app registers", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    Busybody.Registry.register(%{name: "newapp", port: 4500, pid: "200", host: "localhost"})

    # PubSub should push update
    assert render(view) =~ "newapp"
  end

  test "removes app when deregistered", %{conn: conn} do
    Busybody.Registry.register(%{name: "dying", port: 4600, pid: "300", host: "localhost"})
    {:ok, view, html} = live(conn, "/")
    assert html =~ "dying"

    Busybody.Registry.deregister("dying")

    refute render(view) =~ "dying"
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd ~/github/busybody && mix test test/busybody_web/live/directory_live_test.exs
```

Expected: failure — route not defined, module not found.

- [ ] **Step 3: Add the LiveView route**

In `lib/busybody_web/router.ex`, replace the existing `"/"` route in the browser scope:

```elixir
  scope "/", BusybodyWeb do
    pipe_through :browser

    live "/", DirectoryLive
  end
```

Remove any existing `get "/", PageController, :home` line.

- [ ] **Step 4: Implement the LiveView**

Create `lib/busybody_web/live/directory_live.ex`:

```elixir
defmodule BusybodyWeb.DirectoryLive do
  use BusybodyWeb, :live_view

  @tick_interval :timer.seconds(5)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Busybody.Registry.subscribe()
      Process.send_after(self(), :tick, @tick_interval)
    end

    apps = Busybody.Registry.list()

    {:ok, assign(socket, apps: apps, now: DateTime.utc_now())}
  end

  @impl true
  def handle_info({:app_registered, _app}, socket) do
    {:noreply, assign(socket, apps: Busybody.Registry.list())}
  end

  @impl true
  def handle_info({:app_deregistered, _name}, socket) do
    {:noreply, assign(socket, apps: Busybody.Registry.list())}
  end

  @impl true
  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, @tick_interval)
    {:noreply, assign(socket, now: DateTime.utc_now())}
  end

  defp relative_time(dt, now) do
    diff = DateTime.diff(now, dt, :second)

    cond do
      diff < 5 -> "just now"
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      true -> "#{div(diff, 3600)}h ago"
    end
  end

  defp status_color(last_seen, now) do
    diff = DateTime.diff(now, last_seen, :second)

    cond do
      diff < 60 -> "bg-emerald-400"
      diff < 90 -> "bg-amber-400"
      true -> "bg-red-400"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#fffff8] dark:bg-gray-950 transition-colors">
      <header class="border-b border-amber-200/60 dark:border-gray-800">
        <div class="max-w-6xl mx-auto px-6 py-8">
          <h1 class="text-3xl font-light tracking-tight text-gray-900 dark:text-gray-100">
            busybody
          </h1>
          <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            <%= length(@apps) %> <%= if length(@apps) == 1, do: "app", else: "apps" %> running
          </p>
        </div>
      </header>

      <main class="max-w-6xl mx-auto px-6 py-8">
        <%= if @apps == [] do %>
          <div class="text-center py-20">
            <p class="text-gray-400 dark:text-gray-500 text-lg">No apps registered yet.</p>
            <p class="text-gray-400 dark:text-gray-600 text-sm mt-2">
              Add <code class="px-1.5 py-0.5 rounded bg-amber-100/60 dark:bg-gray-800 text-gray-700 dark:text-gray-300 text-xs font-mono">Busybody.Client</code> to your app's supervision tree.
            </p>
          </div>
        <% else %>
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            <%= for app <- Enum.sort_by(@apps, & &1.name) do %>
              <a
                href={"http://#{app.host}:#{app.port}"}
                target="_blank"
                rel="noopener"
                class="group block rounded-lg border border-amber-200/60 dark:border-gray-800
                       bg-white dark:bg-gray-900 p-5
                       hover:border-amber-300 dark:hover:border-gray-700
                       hover:shadow-sm transition-all"
              >
                <div class="flex items-center justify-between mb-3">
                  <h2 class="text-lg font-medium text-gray-900 dark:text-gray-100 group-hover:text-amber-700 dark:group-hover:text-amber-400 transition-colors">
                    <%= app.name %>
                  </h2>
                  <span class={"inline-block w-2.5 h-2.5 rounded-full #{status_color(app.last_seen, @now)}"}></span>
                </div>

                <dl class="space-y-1 text-sm text-gray-600 dark:text-gray-400">
                  <div class="flex justify-between">
                    <dt class="text-gray-400 dark:text-gray-500">host</dt>
                    <dd class="font-mono"><%= app.host %></dd>
                  </div>
                  <div class="flex justify-between">
                    <dt class="text-gray-400 dark:text-gray-500">port</dt>
                    <dd class="font-mono"><%= app.port %></dd>
                  </div>
                  <div class="flex justify-between">
                    <dt class="text-gray-400 dark:text-gray-500">pid</dt>
                    <dd class="font-mono"><%= app.pid %></dd>
                  </div>
                  <div class="flex justify-between">
                    <dt class="text-gray-400 dark:text-gray-500">seen</dt>
                    <dd><%= relative_time(app.last_seen, @now) %></dd>
                  </div>
                </dl>
              </a>
            <% end %>
          </div>
        <% end %>
      </main>
    </div>
    """
  end
end
```

- [ ] **Step 5: Update the root layout for dark mode support**

In `lib/busybody_web/components/layouts/root.html.heex`, add `class="dark"` support to the `<html>` tag. Find the `<html` tag and ensure it has:

```html
<html lang="en" class="[scrollbar-gutter:stable]">
```

Then in the `<head>`, add a script to handle dark mode before any rendering:

```html
<script>
  if (window.matchMedia('(prefers-color-scheme: dark)').matches) {
    document.documentElement.classList.add('dark');
  }
  window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', e => {
    document.documentElement.classList.toggle('dark', e.matches);
  });
</script>
```

Also in `config/config.exs` or `assets/tailwind.config.js`, ensure darkMode is set to `"class"`:

```javascript
// assets/tailwind.config.js
module.exports = {
  darkMode: "class",
  // ... rest of config
}
```

- [ ] **Step 6: Remove default page controller and template**

Delete the generated `PageController` and its test if they exist, since we're replacing `/` with the LiveView. Remove references in the router if not already done in step 3.

- [ ] **Step 7: Run tests to verify they pass**

```bash
cd ~/github/busybody && mix test test/busybody_web/live/directory_live_test.exs
```

Expected: all 4 tests pass.

- [ ] **Step 8: Commit**

```bash
cd ~/github/busybody && git add -A && git commit -m "feat: liveview directory page with tailwind styling"
```

---

### Task 7: Client Module

**Files:**
- Create: `lib/busybody/client.ex`
- Test: `test/busybody/client_test.exs`

- [ ] **Step 1: Write the failing tests**

Create `test/busybody/client_test.exs`:

```elixir
defmodule Busybody.ClientTest do
  use ExUnit.Case, async: false

  alias Busybody.Client

  describe "build_payload/1" do
    test "builds registration payload from opts" do
      payload = Client.build_payload(name: "myapp", port: 4000, host: "devbox")

      assert payload.name == "myapp"
      assert payload.port == 4000
      assert payload.host == "devbox"
      assert is_binary(payload.pid)
    end

    test "defaults host to system hostname" do
      payload = Client.build_payload(name: "myapp", port: 4000)
      {:ok, hostname} = :inet.gethostname()
      assert payload.host == to_string(hostname)
    end

    test "uses system pid" do
      payload = Client.build_payload(name: "myapp", port: 4000)
      assert payload.pid == System.pid() |> to_string()
    end
  end

  describe "resolve_port/1" do
    test "returns port from explicit opt" do
      assert Client.resolve_port(port: 4567) == 4567
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd ~/github/busybody && mix test test/busybody/client_test.exs
```

Expected: compilation error — `Busybody.Client` not found.

- [ ] **Step 3: Implement the Client GenServer**

Create `lib/busybody/client.ex`:

```elixir
defmodule Busybody.Client do
  use GenServer
  require Logger

  @default_registry_url "http://localhost:5150"
  @heartbeat_interval :timer.seconds(60)
  @startup_delay :timer.seconds(2)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :process_name, __MODULE__))
  end

  def build_payload(opts) do
    {:ok, hostname} = :inet.gethostname()

    %{
      name: Keyword.fetch!(opts, :name),
      port: resolve_port(opts),
      pid: System.pid() |> to_string(),
      host: Keyword.get(opts, :host, to_string(hostname))
    }
  end

  def resolve_port(opts) do
    cond do
      Keyword.has_key?(opts, :port) ->
        Keyword.get(opts, :port)

      Keyword.has_key?(opts, :endpoint) ->
        endpoint = Keyword.get(opts, :endpoint)
        config = endpoint.config(:http, [])
        Keyword.get(config, :port, 4000)

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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd ~/github/busybody && mix test test/busybody/client_test.exs
```

Expected: all 4 tests pass.

- [ ] **Step 5: Commit**

```bash
cd ~/github/busybody && git add lib/busybody/client.ex test/busybody/client_test.exs && git commit -m "feat: client genserver with heartbeat registration"
```

---

### Task 8: Integration Test — Full Round Trip

**Files:**
- Create: `test/busybody/integration_test.exs`

- [ ] **Step 1: Write integration test**

Create `test/busybody/integration_test.exs`:

```elixir
defmodule Busybody.IntegrationTest do
  use BusybodyWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup do
    apps = Busybody.Registry.list()
    Enum.each(apps, fn app -> Busybody.Registry.deregister(app.name) end)
    :ok
  end

  test "full round trip: API register -> LiveView shows app -> health check prunes", %{conn: conn} do
    # Start a fake app listener
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)

    # Register via API
    conn
    |> put_req_header("content-type", "application/json")
    |> post("/api/register", %{
      "name" => "fakeapp",
      "port" => port,
      "pid" => "99999",
      "host" => "127.0.0.1"
    })

    # LiveView shows the app
    {:ok, view, html} = live(build_conn(), "/")
    assert html =~ "fakeapp"
    assert html =~ "#{port}"

    # Kill the listener, run health check
    :gen_tcp.close(listen)
    Busybody.HealthChecker.check_all()

    # App should be gone
    assert [] = Busybody.Registry.list()
  end
end
```

- [ ] **Step 2: Run the integration test**

```bash
cd ~/github/busybody && mix test test/busybody/integration_test.exs
```

Expected: test passes.

- [ ] **Step 3: Run full test suite**

```bash
cd ~/github/busybody && mix test
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
cd ~/github/busybody && git add test/busybody/integration_test.exs && git commit -m "test: full round trip integration test"
```

---

### Task 9: Manual Smoke Test

- [ ] **Step 1: Start busybody**

```bash
cd ~/github/busybody && mix phx.server
```

Verify it starts on port 5150. Open `http://localhost:5150` in a browser. Should see the empty state with "busybody" header and "0 apps running".

- [ ] **Step 2: Register a fake app via curl**

```bash
curl -s -X POST http://localhost:5150/api/register \
  -H "Content-Type: application/json" \
  -d '{"name":"paperclip","port":4829,"pid":"12345","host":"localhost"}'
```

The LiveView page should update in real-time to show the paperclip card.

- [ ] **Step 3: Verify dark mode**

Toggle system dark mode (or use browser devtools to emulate `prefers-color-scheme: dark`). Page should switch to dark theme with gray backgrounds.

- [ ] **Step 4: Verify light mode Tufte styling**

In light mode, confirm the background is warm ivory (`#fffff8`), not stark white. Cards should have warm-toned borders.

- [ ] **Step 5: Commit any final tweaks**

```bash
cd ~/github/busybody && git add -A && git commit -m "chore: final styling adjustments from smoke test"
```
