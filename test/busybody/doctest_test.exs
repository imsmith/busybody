defmodule Busybody.DoctestTest do
  @moduledoc false
  use ExUnit.Case, async: true

  doctest Busybody.Registry
  doctest BusybodyWeb.Status
end
