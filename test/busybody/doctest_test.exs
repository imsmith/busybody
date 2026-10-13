defmodule Busybody.DoctestTest do
  @moduledoc false
  use ExUnit.Case, async: true

  doctest Busybody.Registry
  doctest Busybody.Client
  doctest BusybodyWeb.Status
end
