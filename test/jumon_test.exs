defmodule JumonTest do
  use ExUnit.Case, async: true

  doctest Jumon
  doctest Jumon.Action
  doctest Jumon.Shortcut
  doctest Jumon.Match
  doctest Jumon.Messages
  doctest Jumon.History
end
