defmodule Jumon.HistoryCase do
  @moduledoc false
  # The same tests for each place of the history.
  defmacro __using__(opts) do
    quote do
      use ExUnit.Case, async: false

      alias Jumon.History

      setup do
        unquote(opts[:setup]).()
      end

      test "records uses, ranks by frecency, keeps the action", %{mod: mod, opts: opts} do
        key = System.unique_integer([:positive])
        assert mod.recent(opts, key, 10) == []

        :ok = mod.record(opts, key, "home", %{"id" => "home", "name" => "Home"})
        :ok = mod.record(opts, key, "issues:2", %{"id" => "issues:2", "name" => "Ship it"})
        :ok = mod.record(opts, key, "issues:2", %{"id" => "issues:2", "name" => "Ship it!"})

        assert [first, second] = mod.recent(opts, key, 10)
        assert {first.id, second.id} == {"issues:2", "home"}
        assert_in_delta first.score, 2.0, 0.01
        assert first.action["name"] == "Ship it!"
        assert %DateTime{} = first.used_at
        assert [_one] = mod.recent(opts, key, 1)

        # Another person has a history of their own.
        assert mod.recent(opts, key + 1, 10) == []

        :ok = mod.forget(opts, key, "issues:2")
        assert [%{id: "home"}] = mod.recent(opts, key, 10)
      end

      test "keeps the newest entries of a person", %{mod: mod, opts: opts} do
        key = "person-#{System.unique_integer([:positive])}"
        opts = Keyword.put(opts, :max_entries, 3)
        for id <- ~w(a b c d e), do: :ok = mod.record(opts, key, id, nil)
        assert opts |> mod.recent(key, 10) |> Enum.map(& &1.id) |> Enum.sort() == ~w(c d e)
      end
    end
  end
end

defmodule Jumon.History.MemoryTest do
  use Jumon.HistoryCase,
    setup: fn ->
      name = :"history_#{System.unique_integer([:positive])}"
      start_supervised!({Jumon.History.Memory, name: name})
      {:ok, mod: Jumon.History.Memory, opts: [name: name]}
    end
end

defmodule Jumon.History.SQLiteTest do
  alias Ecto.Adapters.SQL.Sandbox

  use Jumon.HistoryCase,
    setup: fn ->
      :ok = Sandbox.checkout(JumonTest.SQLiteRepo)
      {:ok, mod: Jumon.History.Ecto, opts: [repo: JumonTest.SQLiteRepo]}
    end
end

defmodule Jumon.History.PostgresTest do
  alias Ecto.Adapters.SQL.Sandbox

  use Jumon.HistoryCase,
    setup: fn ->
      :ok = Sandbox.checkout(JumonTest.PostgresRepo)
      {:ok, mod: Jumon.History.Ecto, opts: [repo: JumonTest.PostgresRepo]}
    end

  @moduletag :postgres
end

defmodule Jumon.History.FrecencyTest do
  use ExUnit.Case, async: true

  alias Jumon.History

  test "a use ten times a month ago ranks below three this week" do
    now = ~U[2027-03-31 12:00:00Z]
    old = %{id: "old", score: 10.0, used_at: ~U[2027-02-28 12:00:00Z], action: nil}
    new = %{id: "new", score: 3.0, used_at: ~U[2027-03-28 12:00:00Z], action: nil}
    assert [%{id: "new"}, %{id: "old"}] = History.rank([old, new], now, 14)
  end

  test "keys" do
    assert History.key(7) == "7"
    assert History.key("ada") == "ada"
    assert byte_size(History.key({:user, 7})) == 64
  end
end
