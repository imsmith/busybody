defmodule BusybodyWeb.DirectoryLive do
  @moduledoc """
  Live directory of all registered dev apps.

  Subscribes to `Busybody.Registry` PubSub events and re-renders the
  card grid in real-time as apps register, deregister, or get pruned
  by the health checker. A 5-second tick keeps relative timestamps fresh.
  """

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
      diff < 60 -> "bg-success"
      diff < 90 -> "bg-warning"
      true -> "bg-error"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100">
      <div class="max-w-5xl mx-auto px-6 py-12">
        <header class="mb-12">
          <h1 class="text-4xl font-light tracking-tight text-base-content">
            busybody
          </h1>
          <p class="mt-2 text-sm text-base-content/60">
            {length(@apps)} {if length(@apps) == 1, do: "app", else: "apps"} registered
          </p>
        </header>

        <div :if={@apps == []} class="py-16 text-center">
          <p class="text-base-content/40 text-lg font-light">
            No apps registered yet.
          </p>
          <p class="text-base-content/30 text-sm mt-2">
            Apps will appear here as they register via the API.
          </p>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-5">
          <a
            :for={app <- @apps}
            href={"http://#{app.host}:#{app.port}"}
            target="_blank"
            rel="noopener"
            class="block rounded-lg border border-base-300 dark:border-base-300/50
                   bg-base-200/50 dark:bg-base-200/80
                   p-5 transition-all duration-150
                   hover:shadow-md hover:border-base-300/80 dark:hover:border-base-content/20
                   hover:-translate-y-0.5"
          >
            <div class="flex items-start justify-between mb-3">
              <h2 class="text-lg font-medium text-base-content truncate pr-3">
                {app.name}
              </h2>
              <span class={"inline-block w-2.5 h-2.5 rounded-full shrink-0 mt-1.5 #{status_color(app.last_seen, @now)}"}>
              </span>
            </div>

            <dl class="space-y-1 text-sm text-base-content/70">
              <div class="flex justify-between">
                <dt class="text-base-content/50">host</dt>
                <dd class="font-mono text-xs">{app.host}</dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-base-content/50">port</dt>
                <dd class="font-mono text-xs">{app.port}</dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-base-content/50">pid</dt>
                <dd class="font-mono text-xs">{app.pid}</dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-base-content/50">seen</dt>
                <dd class="font-mono text-xs">{relative_time(app.last_seen, @now)}</dd>
              </div>
            </dl>
          </a>
        </div>
      </div>
    </div>
    """
  end
end
