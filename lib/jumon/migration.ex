if Code.ensure_loaded?(Ecto.Migration) do
  defmodule Jumon.Migration do
    @moduledoc """
    The table of `Jumon.History.Ecto`, in a migration of the app.

        $ mix jumon.gen.migration

    writes a migration that calls this module:

        defmodule MyApp.Repo.Migrations.AddJumonHistory do
          use Ecto.Migration

          def up, do: Jumon.Migration.up(version: 1)
          def down, do: Jumon.Migration.down(version: 1)
        end

    The table is `jumon_history`: the person's key, the action's id, the
    action as the browser had it (`jsonb` in PostgreSQL, `TEXT` in SQLite),
    its score, its uses, and the time of the last use, with one row for a
    person and an action. The migration runs on PostgreSQL and on SQLite.

    A later version of Jumon that changes the table will have a version 2,
    and a migration of the app that calls `up(version: 2)`.

    Options: `:version` (1, the only one), `:prefix` (the schema of the
    table, in PostgreSQL).
    """

    use Ecto.Migration

    @current 1

    @doc "Creates the table and its indexes."
    @spec up(keyword()) :: :ok
    def up(opts \\ []) do
      version = Keyword.get(opts, :version, @current)
      prefix = opts[:prefix]

      if version >= 1 do
        create_if_not_exists table(:jumon_history, prefix: prefix) do
          add :key, :string, size: 255, null: false
          add :action_id, :string, size: 512, null: false
          add :action, :map
          add :score, :float, null: false, default: 1.0
          add :uses, :integer, null: false, default: 1
          add :used_at, :utc_datetime_usec, null: false
          timestamps(type: :utc_datetime_usec, updated_at: false)
        end

        create_if_not_exists unique_index(:jumon_history, [:key, :action_id], prefix: prefix)
        create_if_not_exists index(:jumon_history, [:key, :used_at], prefix: prefix)
      end

      :ok
    end

    @doc "Drops the table."
    @spec down(keyword()) :: :ok
    def down(opts \\ []) do
      drop_if_exists table(:jumon_history, prefix: opts[:prefix])
      :ok
    end
  end
end
