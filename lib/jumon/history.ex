defmodule Jumon.History do
  @moduledoc """
  What each person runs from the palette, for its "Recent" group and for
  the order of its results: what a person runs often and lately ranks
  first (frecency).

  The history is kept in one of three places, the `:history` option of
  `use Jumon.Commands`:

    * `:local` (the default) - in the browser's `localStorage`, for each
      browser, with nothing on the server;
    * `{module, opts}` - on the server, for each person on any device, by
      the key that `c:Jumon.Commands.history_key/1` gives:
      `Jumon.History.Ecto` keeps it in the app's database (PostgreSQL or
      SQLite), `Jumon.History.Memory` in memory (ETS), or a module of your own
      with this behaviour;
    * `false` - nowhere.

  See the [History](history.md) guide.

  ## Frecency

  Each use adds one to an action's score, and the score halves every
  `:half_life` days (14 by default) after the last use: an action used ten
  times a month ago ranks below one used three times this week.
  `frecency/3` computes it, the same in the browser.
  """

  @typedoc "An entry of the history."
  @type entry :: %{
          id: String.t(),
          score: float(),
          used_at: DateTime.t(),
          action: map() | nil
        }

  @doc """
  The most recent entries of `key`, at most `limit`, best first. Each has
  the action's id, its score at its last use, the time of that use, and
  the action as the browser had it then (to show it again when it came
  from a search).
  """
  @callback recent(opts :: keyword(), key :: term(), limit :: pos_integer()) :: [entry()]

  @doc "Records a use of the action `id` by `key`."
  @callback record(opts :: keyword(), key :: term(), id :: String.t(), action :: map() | nil) ::
              :ok

  @doc "Removes the action `id` from the history of `key`."
  @callback forget(opts :: keyword(), key :: term(), id :: String.t()) :: :ok

  @half_life_days 14

  @doc """
  The score of an entry at `now`: `score` halved for each `half_life` days
  since `used_at`.

  ## Examples

      iex> Jumon.History.frecency(4.0, ~U[2027-03-01 00:00:00Z], ~U[2027-03-15 00:00:00Z])
      2.0

  """
  @spec frecency(number(), DateTime.t(), DateTime.t(), number()) :: float()
  def frecency(score, used_at, now, half_life_days \\ @half_life_days) do
    days = max(DateTime.diff(now, used_at, :millisecond), 0) / 86_400_000
    score * :math.pow(0.5, days / half_life_days)
  end

  @doc false
  # The new score of an action used now, from its entry (or none).
  @spec bump(entry() | nil, DateTime.t(), number()) :: float()
  def bump(nil, _now, _half_life), do: 1.0

  def bump(%{score: score, used_at: used_at}, now, half_life),
    do: frecency(score, used_at, now, half_life) + 1.0

  @doc false
  @spec half_life(keyword()) :: number()
  def half_life(opts), do: Keyword.get(opts, :half_life, @half_life_days)

  @doc false
  # Sorts entries by their frecency now, best first.
  @spec rank([entry()], DateTime.t(), number()) :: [entry()]
  def rank(entries, now, half_life) do
    entries
    |> Enum.map(&%{&1 | score: frecency(&1.score, &1.used_at, now, half_life)})
    |> Enum.sort_by(&{-&1.score, &1.id})
  end

  @doc false
  # The key as a string, for storage.
  @spec key(term()) :: String.t()
  def key(key) when is_binary(key), do: key
  def key(key) when is_integer(key) or is_atom(key), do: to_string(key)

  def key(key),
    do: :crypto.hash(:sha256, :erlang.term_to_binary(key)) |> Base.encode16(case: :lower)
end
