defmodule BusybodyWeb.DirectoryLive do
  @moduledoc """
  Live directory of all registered dev apps.

  Subscribes to `Busybody.Registry` PubSub events and re-renders the
  card grid in real-time as apps register, deregister, or get pruned
  by the health checker. A 5-second tick keeps relative timestamps fresh.
  """

  use BusybodyWeb, :live_view

  alias BusybodyWeb.Status

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

  attr :app, :map, required: true
  attr :now, DateTime, required: true

  defp service_card(assigns) do
    assigns = assign(assigns, :status, Status.classify(assigns.app.last_seen, assigns.now))

    ~H"""
    <a
      href={"http://#{@app.host}:#{@app.port}"}
      target="_blank"
      rel="noopener"
      class={[
        "service-card block rounded border border-base-300 bg-base-200 p-5",
        "transition-all duration-[120ms] ease-[cubic-bezier(0.2,0,0,1)]",
        @status.level == :down && "is-down"
      ]}
    >
      <div class="flex items-start justify-between mb-3 gap-3">
        <h2 class="text-base font-bold tracking-wider uppercase text-base-content truncate">
          {@app.name}
        </h2>
        <span
          class={["shrink-0 text-sm font-bold tracking-wider whitespace-nowrap", @status.class]}
          aria-label={"status #{@status.label}"}
        >
          {@status.glyph} {@status.label}
        </span>
      </div>

      <dl class="space-y-1 text-xs text-base-content/60">
        <div class="flex justify-between">
          <dt>HOST</dt>
          <dd>{@app.host}</dd>
        </div>
        <div class="flex justify-between">
          <dt>PORT</dt>
          <dd>{@app.port}</dd>
        </div>
        <div class="flex justify-between">
          <dt>PID</dt>
          <dd>{@app.pid}</dd>
        </div>
        <div class="flex justify-between">
          <dt>SEEN</dt>
          <dd>{relative_time(@app.last_seen, @now)}</dd>
        </div>
      </dl>
    </a>
    """
  end

  defp summary(apps, now) do
    total = length(apps)
    levels = Enum.map(apps, &Status.classify(&1.last_seen, now).level)
    warn = Enum.count(levels, &(&1 == :warn))
    down = Enum.count(levels, &(&1 == :down))
    unit = if total == 1, do: "SERVICE", else: "SERVICES"

    ["#{total} #{unit}"]
    |> maybe_clause(warn > 0, "#{warn} WARN")
    |> maybe_clause(down > 0, "#{down} DOWN")
    |> Enum.join(" · ")
  end

  defp maybe_clause(parts, true, clause), do: parts ++ [clause]
  defp maybe_clause(parts, false, _clause), do: parts

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100 font-mono">
      <div class="max-w-5xl mx-auto px-6 py-12">
        <header class="mb-12 flex items-start justify-between">
          <div>
            <h1 class="wordmark text-2xl font-bold uppercase tracking-[0.2em] text-primary">
              busybody
            </h1>
            <p class="mt-2 text-xs tracking-widest text-base-content/60">
              {summary(@apps, @now)}
            </p>
          </div>

          <div class="flex items-center gap-1 rounded border border-base-300 bg-base-200 p-1 text-sm">
            <button
              phx-click={JS.dispatch("phx:set-theme", to: "#theme-system", detail: %{})}
              id="theme-system"
              data-phx-theme="system"
              class="rounded px-2.5 py-1 text-base-content/60 hover:text-base-content hover:bg-base-300 transition-colors"
              title="System"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 20 20"
                fill="currentColor"
                class="w-4 h-4"
              >
                <path
                  fill-rule="evenodd"
                  d="M2 4.25A2.25 2.25 0 0 1 4.25 2h11.5A2.25 2.25 0 0 1 18 4.25v8.5A2.25 2.25 0 0 1 15.75 15h-3.105a3.501 3.501 0 0 1 1.1 1.677A.75.75 0 0 1 13.026 18H6.974a.75.75 0 0 1-.719-1.323A3.501 3.501 0 0 1 7.355 15H4.25A2.25 2.25 0 0 1 2 12.75v-8.5Zm1.5 0a.75.75 0 0 1 .75-.75h11.5a.75.75 0 0 1 .75.75v7.5a.75.75 0 0 1-.75.75H4.25a.75.75 0 0 1-.75-.75v-7.5Z"
                  clip-rule="evenodd"
                />
              </svg>
            </button>
            <button
              phx-click={JS.dispatch("phx:set-theme", to: "#theme-light", detail: %{})}
              id="theme-light"
              data-phx-theme="light"
              class="rounded px-2.5 py-1 text-base-content/60 hover:text-base-content hover:bg-base-300 transition-colors"
              title="Light"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 20 20"
                fill="currentColor"
                class="w-4 h-4"
              >
                <path d="M10 2a.75.75 0 0 1 .75.75v1.5a.75.75 0 0 1-1.5 0v-1.5A.75.75 0 0 1 10 2ZM10 15a.75.75 0 0 1 .75.75v1.5a.75.75 0 0 1-1.5 0v-1.5A.75.75 0 0 1 10 15ZM10 7a3 3 0 1 0 0 6 3 3 0 0 0 0-6ZM15.657 5.404a.75.75 0 1 0-1.06-1.06l-1.061 1.06a.75.75 0 0 0 1.06 1.06l1.061-1.06ZM6.464 14.596a.75.75 0 1 0-1.06-1.06l-1.06 1.06a.75.75 0 0 0 1.06 1.06l1.06-1.06ZM18 10a.75.75 0 0 1-.75.75h-1.5a.75.75 0 0 1 0-1.5h1.5A.75.75 0 0 1 18 10ZM5 10a.75.75 0 0 1-.75.75h-1.5a.75.75 0 0 1 0-1.5h1.5A.75.75 0 0 1 5 10ZM14.596 15.657a.75.75 0 0 0 1.06-1.06l-1.06-1.061a.75.75 0 1 0-1.06 1.06l1.06 1.061ZM5.404 6.464a.75.75 0 0 0 1.06-1.06l-1.06-1.06a.75.75 0 1 0-1.06 1.06l1.06 1.06Z" />
              </svg>
            </button>
            <button
              phx-click={JS.dispatch("phx:set-theme", to: "#theme-dark", detail: %{})}
              id="theme-dark"
              data-phx-theme="dark"
              class="rounded px-2.5 py-1 text-base-content/60 hover:text-base-content hover:bg-base-300 transition-colors"
              title="Dark"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 20 20"
                fill="currentColor"
                class="w-4 h-4"
              >
                <path
                  fill-rule="evenodd"
                  d="M7.455 2.004a.75.75 0 0 1 .26.77 7 7 0 0 0 9.958 7.967.75.75 0 0 1 1.067.853A8.5 8.5 0 1 1 6.647 1.921a.75.75 0 0 1 .808.083Z"
                  clip-rule="evenodd"
                />
              </svg>
            </button>
          </div>
        </header>

        <div :if={@apps == []} class="py-16 text-center">
          <p class="text-base-content/60 text-sm tracking-widest uppercase">
            No services registered
          </p>
          <p class="text-base-content/40 text-xs mt-2">
            apps appear here when they register via the API
          </p>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-5">
          <.service_card :for={app <- @apps} app={app} now={@now} />
        </div>
      </div>
    </div>
    """
  end
end
