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
