defmodule BusybodyWeb.StatusTest do
  @moduledoc false
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
