{:ok, _pid} = Phoenix.PubSub.Supervisor.start_link(name: JumonTest.PubSub)
{:ok, _pid} = JumonTest.Endpoint.start_link()
{:ok, _pid} = Jumon.History.Memory.start_link(name: JumonTest.History)

# The history in a database: SQLite always, PostgreSQL when it is
# reachable (JUMON_TEST_DATABASE_URL, or postgres:postgres@localhost).
File.mkdir_p!(Path.expand("../tmp", __DIR__))

migrate = fn repo ->
  Ecto.Migrator.run(repo, [{0, JumonTest.Migration}], :up, all: true, log: false)
end

defmodule JumonTest.Migration do
  use Ecto.Migration
  def up, do: Jumon.Migration.up()
  def down, do: Jumon.Migration.down()
end

_ = Ecto.Adapters.SQLite3.storage_up(JumonTest.SQLiteRepo.config())
{:ok, _pid} = JumonTest.SQLiteRepo.start_link()
migrate.(JumonTest.SQLiteRepo)
Ecto.Adapters.SQL.Sandbox.mode(JumonTest.SQLiteRepo, :manual)

postgres? =
  case Ecto.Adapters.Postgres.storage_up(JumonTest.PostgresRepo.config()) do
    result when result in [:ok, {:error, :already_up}] ->
      {:ok, _pid} = JumonTest.PostgresRepo.start_link()
      migrate.(JumonTest.PostgresRepo)
      Ecto.Adapters.SQL.Sandbox.mode(JumonTest.PostgresRepo, :manual)
      true

    {:error, reason} ->
      IO.puts(
        "PostgreSQL is not reachable (#{inspect(reason)}): the :postgres tests are excluded"
      )

      false
  end

# The :build tests run `mix jumon.build` (npm and network on the first
# run) and `mix hex.build`: `mix test --include build`.
ExUnit.start(exclude: [:build] ++ if(postgres?, do: [], else: [:postgres]))
