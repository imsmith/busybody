# Busybody Design-System UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-skin the busybody directory page to conform to `~/github/design-system` (Tron theme), with status encoded as color + glyph + word.

**Architecture:** Presentation-only. A new pure `BusybodyWeb.Status` module classifies each service's `last_seen` age into the design system's status set; `DirectoryLive` renders it. `assets/css/app.css` is re-tokened to Tron light/dark chrome plus theme-invariant status colors, glow, and the pulse motion. Martian Mono is self-hosted. No backend, API, routing, or health-checker logic changes.

**Tech Stack:** Elixir / Phoenix LiveView, Tailwind v4 + daisyUI (already vendored), Martian Mono (OFL woff2).

**Spec:** `docs/superpowers/specs/2026-06-11-design-system-ux-design.md`

**Deviation from spec (verified):** The spec listed `lib/busybody_web/components/layouts.ex` for a wordmark swap. `live_view/0` in `lib/busybody_web.ex` uses `use Phoenix.LiveView` with no `:layout`, so the `Layouts.app/1` navbar (and its Phoenix `logo.svg`) is **never rendered on `/`**. The wordmark therefore lives in `DirectoryLive`'s `<h1>`, and `layouts.ex` is left untouched.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `lib/busybody_web/status.ex` *(new)* | Pure status classifier: `last_seen` age → `%{level, glyph, label, class}`. |
| `test/busybody_web/status_test.exs` *(new)* | Unit tests for the classifier at the 60s/90s boundaries. |
| `lib/busybody_web/live/directory_live.ex` | Render: wordmark, summary, empty state, status-encoded cards. Uses `Status`. |
| `test/busybody_web/live/directory_live_test.exs` | Updated assertions for new copy + status rendering. |
| `assets/css/app.css` | Tron light/dark theme tokens, status vars, glow, pulse, Martian Mono `@font-face` + font stack. |
| `priv/static/fonts/` *(new)* | Self-hosted Martian Mono woff2 (400/500/700) + OFL license. |

`static_paths/0` already includes `fonts`, so files in `priv/static/fonts/` are served at `/fonts/...`. No endpoint change needed.

---

## Task 1: Status classifier module

**Files:**
- Create: `lib/busybody_web/status.ex`
- Test: `test/busybody_web/status_test.exs`

- [ ] **Step 1: Write the failing test**

Create `test/busybody_web/status_test.exs`:

```elixir
defmodule BusybodyWeb.StatusTest do
  use ExUnit.Case, async: true
  alias BusybodyWeb.Status

  @now ~U[2026-06-11 12:00:00Z]

  test "healthy (<60s) is OK" do
    s = Status.classify(DateTime.add(@now, -30, :second), @now)
    assert s.level == :ok
    assert s.label == "OK"
    assert s.glyph == "●"
    assert s.class == "st-ok"
  end

  test "stale (>=60s, <90s) is WARN" do
    s = Status.classify(DateTime.add(@now, -75, :second), @now)
    assert s.level == :warn
    assert s.label == "WARN"
    assert s.glyph == "◆"
    assert s.class == "st-warn"
  end

  test "dying (>=90s) is DOWN" do
    s = Status.classify(DateTime.add(@now, -120, :second), @now)
    assert s.level == :down
    assert s.label == "DOWN"
    assert s.glyph == "✖"
    assert s.class == "st-down"
  end

  test "exact 60s boundary is WARN" do
    assert Status.classify(DateTime.add(@now, -60, :second), @now).level == :warn
  end

  test "exact 90s boundary is DOWN" do
    assert Status.classify(DateTime.add(@now, -90, :second), @now).level == :down
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/busybody_web/status_test.exs`
Expected: FAIL — `module BusybodyWeb.Status is not available`.

- [ ] **Step 3: Write minimal implementation**

Create `lib/busybody_web/status.ex`:

```elixir
defmodule BusybodyWeb.Status do
  @moduledoc """
  Maps a service's `last_seen` age onto the design system's status set.

  Encoding is color + glyph + word (never color alone — see the design system's
  accessibility invariant). Thresholds match the health checker's prune window:
  healthy `< 60s`, stale `< 90s`, dying `>= 90s`.

  Glyphs are the reserved status sign-shapes (design-system `tokens/marks.edn`:
  circle / diamond / octagon), as plain Unicode so they render before the
  Martian Mono webfont loads. `class` names a CSS class defined in `app.css`
  that carries the theme-invariant status color (and, for `:down`, the pulse).
  """

  @type level :: :ok | :warn | :down
  @type t :: %{level: level(), glyph: String.t(), label: String.t(), class: String.t()}

  @doc """
  Classify a `last_seen` timestamp relative to `now`.

  ## Examples

      iex> now = ~U[2026-06-11 12:00:00Z]
      iex> BusybodyWeb.Status.classify(DateTime.add(now, -30, :second), now).level
      :ok
      iex> BusybodyWeb.Status.classify(DateTime.add(now, -75, :second), now).label
      "WARN"
      iex> BusybodyWeb.Status.classify(DateTime.add(now, -120, :second), now).class
      "st-down"

  """
  @spec classify(DateTime.t(), DateTime.t()) :: t()
  def classify(last_seen, now) do
    case DateTime.diff(now, last_seen, :second) do
      d when d < 60 -> %{level: :ok, glyph: "●", label: "OK", class: "st-ok"}
      d when d < 90 -> %{level: :warn, glyph: "◆", label: "WARN", class: "st-warn"}
      _ -> %{level: :down, glyph: "✖", label: "DOWN", class: "st-down"}
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/busybody_web/status_test.exs`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/busybody_web/status.ex test/busybody_web/status_test.exs
git commit -m "feat: status classifier (color+glyph+word) for directory"
```

---

## Task 2: Render status-encoded cards, wordmark, summary, empty state

**Files:**
- Modify: `lib/busybody_web/live/directory_live.ex`
- Test: `test/busybody_web/live/directory_live_test.exs`

This task changes only rendered HTML structure/copy and wires in `Status`. CSS (theme colors, glow, pulse, font) lands in Tasks 3–4; until then the page renders unstyled-but-correct.

- [ ] **Step 1: Update the existing LiveView tests for the new copy + status**

The current empty-state test asserts the lowercase `"busybody"` and `"0"`; the redesign uses an uppercase wordmark and the terse summary/empty copy. Replace the file `test/busybody_web/live/directory_live_test.exs` with:

```elixir
defmodule BusybodyWeb.DirectoryLiveTest do
  @moduledoc false
  use BusybodyWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup do
    apps = Busybody.Registry.list()
    Enum.each(apps, fn app -> Busybody.Registry.deregister(app.name) end)
    :ok
  end

  test "renders empty state", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ "busybody"
    assert html =~ "0 SERVICES"
    assert html =~ "No services registered"
  end

  test "shows registered apps with OK status", %{conn: conn} do
    Busybody.Registry.register(%{name: "paperclip", port: 4829, pid: "100", host: "devbox"})

    {:ok, _view, html} = live(conn, "/")
    assert html =~ "paperclip"
    assert html =~ "4829"
    assert html =~ "devbox"
    # freshly registered -> OK, encoded as glyph + word, not color alone
    assert html =~ "OK"
    assert html =~ "1 SERVICE"
  end

  test "updates in real-time when app registers", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    Busybody.Registry.register(%{name: "newapp", port: 4500, pid: "200", host: "localhost"})

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

Run: `mix test test/busybody_web/live/directory_live_test.exs`
Expected: FAIL — `"0 SERVICES"` / `"No services registered"` / `"OK"` not found in current markup.

- [ ] **Step 3: Rewrite the render and helpers**

In `lib/busybody_web/live/directory_live.ex`:

(a) Add an alias under the `use BusybodyWeb, :live_view` line:

```elixir
  use BusybodyWeb, :live_view

  alias BusybodyWeb.Status
```

(b) Delete the `status_color/2` function (the `bg-success`/`bg-warning`/`bg-error` helper — superseded by `Status`).

(c) Add a `service_card/1` function component and a `summary/2` helper. Place them just above `render/1`:

```elixir
  attr :app, :map, required: true
  attr :now, :any, required: true

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
        <div class="flex justify-between"><dt>HOST</dt><dd>{@app.host}</dd></div>
        <div class="flex justify-between"><dt>PORT</dt><dd>{@app.port}</dd></div>
        <div class="flex justify-between"><dt>PID</dt><dd>{@app.pid}</dd></div>
        <div class="flex justify-between"><dt>SEEN</dt><dd>{relative_time(@app.last_seen, @now)}</dd></div>
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
```

(d) Replace the entire `render/1` body with:

```elixir
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
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-4 h-4">
                <path fill-rule="evenodd" d="M2 4.25A2.25 2.25 0 0 1 4.25 2h11.5A2.25 2.25 0 0 1 18 4.25v8.5A2.25 2.25 0 0 1 15.75 15h-3.105a3.501 3.501 0 0 1 1.1 1.677A.75.75 0 0 1 13.026 18H6.974a.75.75 0 0 1-.719-1.323A3.501 3.501 0 0 1 7.355 15H4.25A2.25 2.25 0 0 1 2 12.75v-8.5Zm1.5 0a.75.75 0 0 1 .75-.75h11.5a.75.75 0 0 1 .75.75v7.5a.75.75 0 0 1-.75.75H4.25a.75.75 0 0 1-.75-.75v-7.5Z" clip-rule="evenodd" />
              </svg>
            </button>
            <button
              phx-click={JS.dispatch("phx:set-theme", to: "#theme-light", detail: %{})}
              id="theme-light"
              data-phx-theme="light"
              class="rounded px-2.5 py-1 text-base-content/60 hover:text-base-content hover:bg-base-300 transition-colors"
              title="Light"
            >
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-4 h-4">
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
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-4 h-4">
                <path fill-rule="evenodd" d="M7.455 2.004a.75.75 0 0 1 .26.77 7 7 0 0 0 9.958 7.967.75.75 0 0 1 1.067.853A8.5 8.5 0 1 1 6.647 1.921a.75.75 0 0 1 .808.083Z" clip-rule="evenodd" />
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/busybody_web/live/directory_live_test.exs test/busybody_web/status_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/busybody_web/live/directory_live.ex test/busybody_web/live/directory_live_test.exs
git commit -m "feat: status-encoded cards, wordmark, terse summary in directory"
```

---

## Task 3: Tron theme tokens, status colors, glow, pulse (`app.css`)

**Files:**
- Modify: `assets/css/app.css`

No ExUnit coverage (pure CSS). Verification is an asset build plus visual check in Task 5.

- [ ] **Step 1: Re-token the `dark` theme block**

In `assets/css/app.css`, in the `@plugin "../vendor/daisyui-theme" { name: "dark"; ... }` block, replace the `--color-*` lines (keep `name`/`default`/`prefersdark`/`color-scheme`/`--radius-*`/`--size-*`/`--border`/`--depth`/`--noise`) with Tron dark chrome. Values copied verbatim from `~/github/design-system/tokens/color/themes.edn` `:tron :dark`:

```css
  /* Tron dark — design-system tokens/color/themes.edn :tron :dark (chrome only) */
  --color-base-100: #05080a;   /* bg */
  --color-base-200: #0a141a;   /* surface */
  --color-base-300: #0f1c24;   /* raised step (derived: one stop above surface) */
  --color-base-content: #cfeff5; /* text (muted = base-content at /60 in markup) */
  --color-primary: #00E5FF;    /* accent */
  --color-primary-content: #000000; /* on-accent */
  --color-secondary: #00E5FF;
  --color-secondary-content: #000000;
  --color-accent: #00E5FF;
  --color-accent-content: #000000;
  --color-neutral: #6d8288;    /* border */
  --color-neutral-content: #cfeff5;
  --color-info: #00E5FF;
  --color-info-content: #000000;
  --color-success: #2fd44e;
  --color-success-content: #05080a;
  --color-warning: #ffd400;
  --color-warning-content: #05080a;
  --color-error: #ff2740;
  --color-error-content: #ffffff;
  --border: 1.5px;
```

- [ ] **Step 2: Re-token the `light` theme block**

In the `name: "light"` block, replace the `--color-*` lines with Tron light chrome, verbatim from `themes.edn` `:tron :light`:

```css
  /* Tron light — design-system tokens/color/themes.edn :tron :light (chrome only) */
  --color-base-100: #eef7f9;   /* bg */
  --color-base-200: #ffffff;   /* surface */
  --color-base-300: #dfeaed;   /* raised/border step (derived) */
  --color-base-content: #07232a; /* text (muted = base-content at /60 in markup) */
  --color-primary: #008c9e;    /* accent (darkened for light per themes.edn) */
  --color-primary-content: #ffffff; /* on-accent */
  --color-secondary: #008c9e;
  --color-secondary-content: #ffffff;
  --color-accent: #008c9e;
  --color-accent-content: #ffffff;
  --color-neutral: #adb6b9;    /* border */
  --color-neutral-content: #07232a;
  --color-info: #008c9e;
  --color-info-content: #ffffff;
  --color-success: #2fd44e;
  --color-success-content: #07232a;
  --color-warning: #ffd400;
  --color-warning-content: #07232a;
  --color-error: #ff2740;
  --color-error-content: #ffffff;
  --border: 1.5px;
```

- [ ] **Step 3: Add theme-invariant status colors, glow, pulse, and the status/card classes**

Append to the end of `assets/css/app.css`:

```css
/* ── Design system: status (theme-invariant) ───────────────────────────────
   Values from design-system tokens/color/status.edn. These do NOT live in a
   theme block — the light/dark switcher must not touch data color. */
:root {
  --status-ok:   #2fd44e; /* status.edn :low     */
  --status-warn: #ffd400; /* status.edn :medium  */
  --status-down: #ff2740; /* status.edn :critical */
  --ds-glow:     #00E5FF; /* themes.edn :tron :glow */
}

.st-ok   { color: var(--status-ok); }
.st-warn { color: var(--status-warn); }
.st-down { color: var(--status-down); }

/* A DOWN card takes a critical border (component matrix: error state). */
.service-card.is-down { border-color: var(--status-down); }

/* ── Glow (design-system tokens/material.edn): dark surfaces only ──────────── */
.wordmark { text-shadow: 0 0 8px color-mix(in srgb, var(--ds-glow) 55%, transparent); }
.service-card:hover {
  border-color: var(--color-primary);
  box-shadow: 0 0 10px color-mix(in srgb, var(--ds-glow) 25%, transparent);
  transform: translateY(-1px);
}
/* Suppress glow on the light theme (glow sits on dark material only). */
[data-theme="light"] .wordmark { text-shadow: none; }
[data-theme="light"] .service-card:hover { box-shadow: none; }

/* ── Focus (design-system component matrix): outline is the signal ────────── */
.service-card:focus-visible {
  outline: 2px solid var(--color-base-content);
  outline-offset: 4px;
}

/* ── The one status motion: pulse on DOWN (tokens/motion.edn) ──────────────── */
@keyframes ds-pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.45; } }
.st-down { animation: ds-pulse 1500ms ease-in-out infinite; }

@media (prefers-reduced-motion: reduce) {
  .st-down { animation: none; }
}
```

- [ ] **Step 4: Build assets to verify the CSS compiles**

Run: `mix assets.build`
Expected: completes with no Tailwind/daisyUI errors; `priv/static/assets/css/app.css` is regenerated.

- [ ] **Step 5: Commit**

```bash
git add assets/css/app.css priv/static/assets/css/app.css
git commit -m "feat: Tron theme tokens, status colors, glow, pulse in app.css"
```

---

## Task 4: Self-host Martian Mono

**Files:**
- Create: `priv/static/fonts/martian-mono-400.woff2`, `-500.woff2`, `-700.woff2`, `priv/static/fonts/OFL.txt`
- Modify: `assets/css/app.css`

- [ ] **Step 1: Fetch the woff2 files and license**

Martian Mono is OFL-1.1. Fetch the pre-built latin woff2 (weights 400/500/700) and the license from the Fontsource CDN (jsDelivr). Run:

```bash
mkdir -p priv/static/fonts
base="https://cdn.jsdelivr.net/npm/@fontsource/martian-mono@5/files"
curl -fsSL "$base/martian-mono-latin-400-normal.woff2" -o priv/static/fonts/martian-mono-400.woff2
curl -fsSL "$base/martian-mono-latin-500-normal.woff2" -o priv/static/fonts/martian-mono-500.woff2
curl -fsSL "$base/martian-mono-latin-700-normal.woff2" -o priv/static/fonts/martian-mono-700.woff2
curl -fsSL "https://cdn.jsdelivr.net/npm/@fontsource/martian-mono@5/LICENSE" -o priv/static/fonts/OFL.txt
ls -l priv/static/fonts/
```

Expected: three non-empty `.woff2` files and `OFL.txt`. If the CDN is unreachable, fetch the same files from the Google Fonts release of Martian Mono (https://fonts.google.com/specimen/Martian+Mono) or the source repo (https://github.com/evilmartians/mono) and convert the static TTFs to woff2 with `woff2_compress` inside a distrobox; name the outputs as above.

- [ ] **Step 2: Add `@font-face` and the font stack**

In `assets/css/app.css`, add near the top (after the `@import`/`@source`/`@plugin` lines, before the theme blocks):

```css
/* ── Martian Mono (OFL-1.1) — the design system's mono "voice" ──────────────
   Self-hosted; see priv/static/fonts/OFL.txt. Served from /fonts via
   BusybodyWeb.static_paths/0. */
@font-face {
  font-family: "Martian Mono";
  font-style: normal;
  font-weight: 400;
  font-display: swap;
  src: url("/fonts/martian-mono-400.woff2") format("woff2");
}
@font-face {
  font-family: "Martian Mono";
  font-style: normal;
  font-weight: 500;
  font-display: swap;
  src: url("/fonts/martian-mono-500.woff2") format("woff2");
}
@font-face {
  font-family: "Martian Mono";
  font-style: normal;
  font-weight: 700;
  font-display: swap;
  src: url("/fonts/martian-mono-700.woff2") format("woff2");
}

/* Route Tailwind's `font-mono` utility (used on the page root) through Martian
   Mono first, then system monospace. Tailwind v4 reads the stack from @theme. */
@theme {
  --font-mono: "Martian Mono", ui-monospace, "SF Mono", Menlo, Consolas, monospace;
}
```

- [ ] **Step 3: Build assets and confirm the font is referenced**

Run: `mix assets.build && grep -c "Martian Mono" priv/static/assets/css/app.css`
Expected: build succeeds; grep prints a non-zero count.

- [ ] **Step 4: Commit**

```bash
git add priv/static/fonts assets/css/app.css priv/static/assets/css/app.css
git commit -m "feat: self-host Martian Mono webfont (OFL)"
```

---

## Task 5: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Full test suite**

Run: `mix test`
Expected: all pass (includes the doctest in `Status`, the status unit tests, and the LiveView tests). Fix any failure before continuing.

- [ ] **Step 2: Formatting and compile warnings**

Run: `mix format --check-formatted && mix compile --warnings-as-errors`
Expected: no formatting diffs, no warnings.

- [ ] **Step 3: Manual visual check**

Run: `mix phx.server` and open `http://localhost:5150`. Then register three apps with curl so they age into different states:

```bash
curl -s -XPOST http://localhost:5150/api/register -H 'content-type: application/json' -d '{"name":"wagger","port":4001,"pid":"61231","host":"localhost"}' >/dev/null
curl -s -XPOST http://localhost:5150/api/register -H 'content-type: application/json' -d '{"name":"cliff","port":4829,"pid":"12044","host":"localhost"}' >/dev/null
curl -s -XPOST http://localhost:5150/api/register -H 'content-type: application/json' -d '{"name":"comn","port":4007,"pid":"8810","host":"localhost"}' >/dev/null
```

Confirm:
- Dark theme by default; wordmark `BUSYBODY` glows cyan; summary reads `3 SERVICES`.
- Each card shows glyph + word + color (`● OK`). Wait ~60s without re-registering and a card flips to `◆ WARN`, then `✖ DOWN` (pulsing) past 90s.
- The switcher cycles system / light / dark; status colors are identical in light and dark; glow disappears on light.
- DevTools → emulate `prefers-reduced-motion: reduce` → the DOWN pulse goes static.
- Tab to a card: 2px outline at 4px offset appears.

- [ ] **Step 4: Final commit (only if Step 2 produced formatting changes)**

```bash
git add -A
git commit -m "chore: format after design-system UX pass"
```

---

## Self-Review notes

- **Spec coverage:** §1 theme tokens → Task 3; §2 cards + status encoding → Tasks 1–2; §3 header/voice/empty state → Task 2; §4 motion/a11y → Task 3 (pulse, focus, reduced-motion) + Task 1 (color-independent encoding); §5 typography → Task 4. Spec's `layouts.ex` item dropped with documented reason (function not on the route).
- **Status class names** are consistent across tasks: `st-ok` / `st-warn` / `st-down` (Task 1 returns them; Task 3 defines them) and `is-down` (Task 2 applies it; Task 3 styles it).
- **Muted text** uses `text-base-content/60` (Task 2) rather than a custom var — daisyUI's theme plugin governs chrome vars and may drop unrecognized ones, and base-content opacity tracks the active theme by construction.
- **`--font-mono`** is set via Tailwind v4 `@theme` (Task 4) so the `font-mono` utility on the page root (Task 2) resolves to Martian Mono.
