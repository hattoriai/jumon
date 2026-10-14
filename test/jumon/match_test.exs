defmodule Jumon.MatchTest do
  use ExUnit.Case, async: true

  alias Jumon.Match

  # test/fixtures/match.json holds the scores of these rules, which the
  # TypeScript matcher must give too (assets/test/match.test.ts).
  test "the fixture is what Jumon.Match gives" do
    cases = "test/fixtures/match.json" |> File.read!() |> JSON.decode!()
    assert length(cases) > 40

    for %{"action" => action, "query" => query, "expected" => expected} <- cases do
      result =
        Match.score(
          Jumon.action(:x, action["name"],
            keywords: action["keywords"],
            subtitle: action["subtitle"],
            section: action["section"],
            priority: action["priority"]
          ),
          query
        )

      assert (result && %{"score" => result.score, "positions" => result.positions}) == expected,
             "#{inspect(query)} in #{inspect(action["name"])}"
    end
  end

  test "ranks the best first, and keeps the order of equals" do
    actions = [
      Jumon.action(:a, "My settings"),
      Jumon.action(:b, "Settings"),
      Jumon.action(:c, "Set priority"),
      Jumon.action(:d, "Sign out"),
      Jumon.action(:e, "Reset", priority: 500)
    ]

    assert actions |> Match.rank("settings") |> Enum.map(&elem(&1, 0).id) == ["b", "a"]
    assert actions |> Match.rank("set") |> Enum.map(&elem(&1, 0).id) == ["e", "b", "c", "a"]
    assert actions |> Match.rank("") |> length() == 5
  end

  test "one typo in a long word" do
    assert Match.score(Jumon.action(:a, "Issues"), "isues")
    assert Match.score(Jumon.action(:a, "Issues"), "isseus")
    refute Match.score(Jumon.action(:a, "Issues"), "iuesz")
    assert Match.score(Jumon.action(:a, "Sign out", keywords: ["logout"]), "lgout")
  end

  test "maps as the browser has them" do
    assert %{positions: [0]} = Match.score(%{"name" => "Home", "keywords" => []}, "h")
  end
end
