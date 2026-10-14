if Code.ensure_loaded?(Ecto.Query) do
  defmodule Jumon.History.Entry do
    @moduledoc false
    # A row of the history table (see Jumon.Migration).
    use Ecto.Schema

    schema "jumon_history" do
      field :key, :string
      field :action_id, :string
      field :action, :map
      field :score, :float
      field :uses, :integer, default: 1
      field :used_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end
  end

  defmodule Jumon.History.Ecto do
    @moduledoc """
    A `Jumon.History` in the app's database, with Ecto: PostgreSQL or
    SQLite (`ecto_sqlite3`), in the `jumon_history` table.

        use Jumon.Commands, history: {Jumon.History.Ecto, repo: MyApp.Repo}

    Make the table with a migration (`mix jumon.gen.migration`, see
    `Jumon.Migration`). The app needs `ecto_sql` and its adapter in its
    deps, as an app with a repo has.

    Options:

      * `:repo` (required) - the app's `Ecto.Repo`.
      * `:prefix` - the schema (PostgreSQL) of the table.
      * `:max_entries` - the most entries of a person, 200 by default; the
        oldest go first.
      * `:half_life` - in days, see `Jumon.History`.

    A use updates the person's row of the action, or adds it, in one
    statement that both databases run (`INSERT ... ON CONFLICT DO
    UPDATE`).
    """

    @behaviour Jumon.History

    import Ecto.Query

    alias Jumon.History
    alias Jumon.History.Entry

    @impl History
    def recent(opts, key, limit) do
      repo = Keyword.fetch!(opts, :repo)
      key = History.key(key)

      from(e in Entry,
        where: e.key == ^key,
        order_by: [desc: e.used_at, desc: e.id],
        limit: 100
      )
      |> repo.all(prefix: opts[:prefix])
      |> Enum.map(&%{id: &1.action_id, score: &1.score, used_at: &1.used_at, action: &1.action})
      |> History.rank(DateTime.utc_now(), History.half_life(opts))
      |> Enum.take(limit)
    end

    @impl History
    def record(opts, key, id, action) do
      repo = Keyword.fetch!(opts, :repo)
      prefix = opts[:prefix]
      key = History.key(key)
      now = DateTime.utc_now()

      old =
        from(e in Entry, where: e.key == ^key and e.action_id == ^id)
        |> repo.one(prefix: prefix)

      score =
        History.bump(
          old && %{score: old.score, used_at: old.used_at},
          now,
          History.half_life(opts)
        )

      entry = %Entry{
        key: key,
        action_id: id,
        action: action,
        score: score,
        uses: 1,
        used_at: now,
        inserted_at: now
      }

      repo.insert!(entry,
        prefix: prefix,
        conflict_target: [:key, :action_id],
        on_conflict: [set: [score: score, used_at: now, action: action], inc: [uses: 1]]
      )

      prune(repo, prefix, key, Keyword.get(opts, :max_entries, 200))
      :ok
    end

    @impl History
    def forget(opts, key, id) do
      repo = Keyword.fetch!(opts, :repo)
      key = History.key(key)

      from(e in Entry, where: e.key == ^key and e.action_id == ^id)
      |> repo.delete_all(prefix: opts[:prefix])

      :ok
    end

    # Deletes the person's entries but the newest `max`. SQLite has no
    # OFFSET without LIMIT, so the query keeps a LIMIT, which both run.
    defp prune(repo, prefix, key, max) do
      keep =
        from(e in Entry,
          where: e.key == ^key,
          order_by: [desc: e.used_at, desc: e.id],
          limit: ^max,
          select: e.id
        )

      from(e in Entry, where: e.key == ^key and e.id not in subquery(keep))
      |> repo.delete_all(prefix: prefix)
    end
  end
end
