defmodule Mix.Tasks.Jumon.Gen.Migration do
  @shortdoc "Generates the migration of the history table (Jumon.History.Ecto)"

  @moduledoc """
  Generates a migration for the table of `Jumon.History.Ecto`, in the
  migrations of the app's repo.

      $ mix jumon.gen.migration
      $ mix jumon.gen.migration --repo MyApp.Repo

  The migration calls `Jumon.Migration`, which makes the same table on
  PostgreSQL and on SQLite. Run it with `mix ecto.migrate`, then keep the
  history there:

      use Jumon.Commands, history: {Jumon.History.Ecto, repo: MyApp.Repo}

  ## Options

    * `--repo` - the repo, when the app has more than one (the first of
      `:ecto_repos` otherwise).
    * `--prefix` - the schema of the table, in PostgreSQL.
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    {opts, _args} = OptionParser.parse!(argv, strict: [repo: :string, prefix: :string])
    Mix.Task.run("loadpaths")
    config = Mix.Project.config()
    app = config[:app]

    repo =
      case opts[:repo] do
        nil -> Application.get_env(app, :ecto_repos, []) |> List.first()
        name -> Module.concat([name])
      end

    unless repo do
      Mix.raise("mix jumon.gen.migration found no repo; give one with --repo MyApp.Repo")
    end

    dir = migrations_dir(app, repo)

    case Path.wildcard(Path.join(dir, "*_add_jumon_history.exs")) do
      [existing | _rest] ->
        Mix.shell().info([:green, "* unchanged ", :reset, existing, " (the migration exists)"])

      [] ->
        path = Path.join(dir, "#{timestamp()}_add_jumon_history.exs")
        File.mkdir_p!(dir)
        File.write!(path, migration(repo, opts[:prefix]))
        Mix.shell().info([:green, "* creating ", :reset, path])
    end
  end

  @doc false
  @spec migration(module(), String.t() | nil) :: String.t()
  def migration(repo, prefix) do
    args = if prefix, do: ~s(version: 1, prefix: "#{prefix}"), else: "version: 1"

    """
    defmodule #{inspect(repo)}.Migrations.AddJumonHistory do
      use Ecto.Migration

      # The history of the command palette, see Jumon.History.Ecto.
      def up, do: Jumon.Migration.up(#{args})
      def down, do: Jumon.Migration.down(#{args})
    end
    """
  end

  defp migrations_dir(app, repo) do
    priv =
      case Application.get_env(app, repo, [])[:priv] do
        nil -> Path.join("priv", repo |> Module.split() |> List.last() |> Macro.underscore())
        priv -> priv
      end

    Path.join(priv, "migrations")
  end

  defp timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    :io_lib.format("~4..0B~2..0B~2..0B~2..0B~2..0B~2..0B", [y, m, d, hh, mm, ss]) |> to_string()
  end
end
