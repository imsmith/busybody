# Busybody UX — apply the Design System

Date: 2026-06-11
Status: Approved for planning
Source of truth: `~/github/design-system` (`design.md`, `manual/`, `tokens/`)

## Summary

Re-skin the busybody directory page to conform to the design system. Busybody
is a local-dev service monitor; the design system is a data-legible, CRT-rooted
ops aesthetic — a strong fit. This is a **presentation-only** change. The
registry, health checker, API, and client are untouched; no behavior changes
except how status is rendered.

Decisions locked during brainstorming:

- **Direction A** — keep the responsive clickable card grid, restyle it.
- **Theme: Tron (cyan).** Its accent (`#00E5FF`) is the only anchor that does
  not collide with a status hue. Chosen over Matrix (green chrome vs green=OK)
  and Compaq (amber chrome vs amber=WARN).
- **Keep the existing system / light / dark switcher.** Re-token the two
  daisyUI themes to Tron light + Tron dark; leave the switcher mechanism as-is.
- **Martian Mono only.** Every element on the page is the system's mono "voice";
  there is no long-form prose, so the proportional companion (Martian Grotesk)
  is not needed. Self-host Martian Mono (OFL) as woff2, system-monospace
  fallback.

## Hard invariants honored (from `design.md`)

- **Data color is theme-invariant.** OK/WARN/DOWN status colors are the same in
  light and dark; the switcher touches chrome only.
- **Never color alone.** Status is color **+ glyph + word**, replacing today's
  bare colored dot (which violates the system).
- **Glow is dark-only.** Ambient/active glow on dark surfaces; suppressed on
  light.
- **Respect `prefers-reduced-motion`.** The one status motion (pulse) goes
  static.
- **Reserved status sign-shapes** are used only for status, never as UI chrome.

## Scope

### Files touched

| File | Change |
| --- | --- |
| `assets/css/app.css` | Re-token `light`/`dark` daisyUI themes to Tron; add Martian Mono `@font-face`; add theme-invariant status color vars. |
| `assets/fonts/` *(new)* | Self-hosted Martian Mono woff2 (OFL) + its license file. |
| `lib/busybody_web/live/directory_live.ex` | Restyle header + cards; status as glyph+word+color; count summary; empty state. |
| `lib/busybody_web/components/layouts.ex` | Wordmark in place of Phoenix `logo.svg`; keep `theme_toggle/1` switcher behavior. |
| `lib/busybody_web/components/layouts/root.html.heex` | No structural change; confirm font/asset wiring. |

### Out of scope

- `core_components.ex` — the generated Phoenix kit. Left as-is; the directory
  page does not depend on it for the restyled surfaces. If a shared component
  (e.g. `flash`) appears, it inherits the new theme tokens automatically and is
  not separately redesigned in this pass.
- All backend modules (`Busybody.Registry`, `HealthChecker`, `Client`),
  `ApiController`, routing, and tests of behavior. The status-threshold logic
  itself does not change — only its rendered form.

## §1 — Theme tokens (`assets/css/app.css`)

Keep the daisyUI two-theme + `@custom-variant dark` machinery exactly as it
works today. Replace the **values** of the `light` and `dark` theme blocks with
Tron chrome, copied verbatim from `tokens/color/themes.edn` and cited in a
comment. Map design-system roles onto the daisyUI variables already in use:

| DS role | daisyUI var | Tron dark | Tron light |
| --- | --- | --- | --- |
| `bg` | `--color-base-100` | `#05080a` | `#eef7f9` |
| `surface` | `--color-base-200` | `#0a141a` | `#ffffff` |
| (raised) | `--color-base-300` | derived darker/lighter step | derived |
| `text` | `--color-base-content` | `#cfeff5` | `#07232a` |
| `accent` | `--color-primary` / `--color-accent` | `#00E5FF` | `#008c9e` |
| `on-accent` | `--color-primary-content` | `#000000` | `#ffffff` |
| `border` | `--color-neutral` / border token | `#6d8288` | `#adb6b9` |
| `glow` | (custom var, see below) | `#00E5FF` | `#00E5FF` |

`muted` (`#a2bdc3` dark / `#6d7d81` light) is applied at the component level for
secondary text. Set `--border: 1.5px` (already present). Radius stays at the
system's small values.

### Status color vars (theme-invariant)

Defined once, **outside** the theme blocks so the switcher cannot touch them
(values from `tokens/color/status.edn`):

```css
:root {
  --status-ok:   #2fd44e; /* status.edn :low     */
  --status-warn: #ffd400; /* status.edn :medium  */
  --status-down: #ff2740; /* status.edn :critical */
  --glow: #00E5FF;        /* themes.edn :tron :glow */
}
```

On light surfaces these status hues may be darkened per-instance only if APCA
contrast demands it (verify with `tools/contrast/`); the canonical values above
are the default.

### Glow (`tokens/material.edn`)

Two levels, dark surfaces only. `ambient` (resting accent elements / hover) and
`active` (DOWN pulse). Implemented as `box-shadow` on controls/cards and
`text-shadow` on the accent wordmark. Suppressed under the `light` theme. Never
on body text, muted text, borders, or data fills.

## §2 — Card component & status encoding (`directory_live.ex`)

Layout unchanged: responsive grid `grid-cols-1 sm:grid-cols-2 lg:grid-cols-3`,
each card a full `<a>` to `http://{host}:{port}` (`target="_blank"`,
`rel="noopener"`).

Card content (all Martian Mono):

- **Name** — uppercase, letter-spaced, `text` color, truncating.
- **Status** — glyph + word + color, top-right. See mapping below.
- **Meta** — `host:port` and relative `seen`, `muted` color, `caption`/`small`
  size.

### Status mapping

`status_color/2` is replaced by a `status/2` helper returning the triple
`{glyph, word, css_var}`. Thresholds are today's logic, unchanged:

| Condition | Glyph (Unicode) | Word | Color var | DS step |
| --- | --- | --- | --- | --- |
| `seen < 60s` | `●` (U+25CF) | `OK` | `--status-ok` | `low` |
| `60s ≤ seen < 90s` | `◆` (U+25C6) | `WARN` | `--status-warn` | `medium` |
| `seen ≥ 90s` | `✖` (U+2716) | `DOWN` | `--status-down` | `critical` |

Glyphs are plain Unicode (render in any monospace font, before the webfont
loads). They correspond to the reserved status shapes circle / diamond /
octagon (`tokens/marks.edn`). An `aria-label` carries the word for SR users.

### States (`tokens/components.edn` matrix)

- `default` — surface fill, border, no glow.
- `hover` — border → `accent`, ambient box-glow (dark only), 1px lift.
- `focus` — 2px outline in `text` color, 4px offset (the focus signal), active
  glow. Outline is the signal, not a color swap.
- A DOWN card additionally takes a `critical`-colored border.

## §3 — Header, voice, empty state

- **Wordmark** — `BUSYBODY`, accent color, accent `text-shadow` glow (dark).
  Replaces the Phoenix `logo.svg` in `layouts.ex`.
- **Summary line** — terse operational voice (`tokens/voice.edn`):
  `N SERVICES · n WARN · n DOWN`. Drop any zero-count clause; never pad. When
  all healthy: `N SERVICES`. Singular `1 SERVICE`.
- **Empty state** — what-happened / what-to-do shape:
  `NO SERVICES REGISTERED` then `apps appear here when they register via the API`.
- **Status lexicon** — display words map to the system steps:
  `low→OK`, `medium→WARN`, `critical→DOWN` (`tokens/voice.edn`).

## §4 — Motion & accessibility

- **Pulse** (`tokens/motion.edn`) — the single status motion: opacity (+glow)
  on the DOWN status indicator, 1500ms period. Reinforcement only; color + glyph
  + word already signal. Nothing else animates beyond standard hover/focus
  transitions (`fast 120ms`, easing `cubic-bezier(0.2,0,0,1)`).
- **`prefers-reduced-motion`** — pulse and the existing reconnect spinner go
  static. Hover/focus state changes remain (they are not "travel").
- **Color independence** — every status is also a glyph and a word; the page is
  fully legible in grayscale.
- **Focus** — visible 2px `text`-color outline at 4px offset on the card links
  and switcher buttons.
- **Contrast** — chrome pairs are APCA-verified in `themes.edn`; if any
  per-instance status-on-light combination is introduced, verify it with
  `tools/contrast/` inside a distrobox before shipping.

## §5 — Typography (`assets/css/app.css`, `assets/fonts/`)

- Self-host **Martian Mono** (OFL-1.1) as woff2 under `assets/fonts/`, weights
  400 / 500 / 700, via `@font-face`. Include the OFL license file alongside.
- Font stack: `"Martian Mono", ui-monospace, "SF Mono", Menlo, Consolas,
  monospace`. Applied page-wide (it is all "voice").
- No Martian Grotesk (no long-form prose on this page).
- Type scale from `tokens/typography.edn`: wordmark ~`h2 24`, names `body 16`,
  meta `caption 12`/`small 14`, summary `small 14`. Snug line-height 1.4 for
  data; tight 1.15 for the wordmark. Hierarchy via uppercase + weight +
  letter-spacing (mono-native), not size alone.

## Verification

- Page renders in dark (default) and light; switcher cycles system/light/dark.
- Status colors identical across both modes (theme-invariant check).
- Every status shows glyph + word + color; legible with color removed.
- DOWN card pulses; goes static under `prefers-reduced-motion`.
- No hardcoded color that exists as a token (each inlined value cites its edn
  source in a comment).
- `mix phx.server`, load `http://localhost:5150`, register a few apps via the
  API, confirm OK/WARN/DOWN transitions as `seen` ages.
