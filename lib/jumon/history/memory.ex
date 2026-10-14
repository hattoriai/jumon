defmodule Jumon.History.Memory do
  @moduledoc """
  A `Jumon.History` in memory, in an ETS table: for development, tests,
  and an app with one node that can lose the history when it restarts.

  Start it in the app's supervision tree, with a name:

      children = [
        {Jumon.History.Memory, name: MyApp.CommandHistory},
        ...
      ]

  and give the name to the commands:

      use Jumon.Commands, history: {Jumon.History.Memory, name: MyApp.CommandHistory}

  Options: `:name` (required), `:max_entries` (the most entries of a
  person, 200 by default; the oldest go first) and `:half_life` (in days,
  see `Jumon.History`).
  """

  @behaviour Jumon.History

  use GenServer

  alias Jumon.History

  @doc false
  def child_spec(opts) do
    %{id: {__MODULE__, Keyword.fetch!(opts, :name)}, start: {__MODULE__, :start_link, [opts]}}
  end

  @doc "Starts the table's owner."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, name, name: name)
  end

  @impl GenServer
  def init(name) do
    :ets.new(table(name), [:named_table, :public, :set, read_concurrency: true])
    {:ok, name}
  end

  @impl History
  def recent(opts, key, limit) do
    key = History.key(key)

    opts
    |> table_of()
    |> :ets.match_object({{key, :_}, :_})
    |> Enum.map(fn {{_key, _id}, entry} -> entry end)
    |> History.rank(DateTime.utc_now(), History.half_life(opts))
    |> Enum.take(limit)
  end

  @impl History
  def record(opts, key, id, action) do
    key = History.key(key)
    table = table_of(opts)
    now = DateTime.utc_now()

    old =
      case :ets.lookup(table, {key, id}) do
        [{_key, entry}] -> entry
        [] -> nil
      end

    entry = %{
      id: id,
      score: History.bump(old, now, History.half_life(opts)),
      used_at: now,
      action: action
    }

    :ets.insert(table, {{key, id}, entry})
    prune(table, key, Keyword.get(opts, :max_entries, 200))
    :ok
  end

  @impl History
  def forget(opts, key, id) do
    :ets.delete(table_of(opts), {History.key(key), id})
    :ok
  end

  defp prune(table, key, max) do
    entries = :ets.match_object(table, {{key, :_}, :_})

    if length(entries) > max do
      entries
      |> Enum.sort_by(fn {_key, entry} -> entry.used_at end, {:desc, DateTime})
      |> Enum.drop(max)
      |> Enum.each(fn {table_key, _entry} -> :ets.delete(table, table_key) end)
    end
  end

  defp table_of(opts), do: opts |> Keyword.fetch!(:name) |> table()
  defp table(name), do: :"#{name}.Table"
end
