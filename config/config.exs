import Config

if config_env() == :dev do
  # The palette bundles. NODE_PATH is unset: the bundles never pick up a
  # package from deps/.
  esbuild_args = ~w(
    src/index.ts
    --bundle
    --minify
    --target=es2020
    --external:phoenix
    --external:phoenix_live_view
  )

  config :esbuild,
    version: "0.28.2",
    jumon_esm: [
      args: esbuild_args ++ ~w(--format=esm --outfile=../priv/static/jumon.esm.js),
      cd: Path.expand("../assets", __DIR__),
      env: %{"NODE_PATH" => nil}
    ],
    jumon_cjs: [
      args: esbuild_args ++ ~w(--format=cjs --outfile=../priv/static/jumon.cjs.js),
      cd: Path.expand("../assets", __DIR__),
      env: %{"NODE_PATH" => nil}
    ]
end

if config_env() == :test do
  config :logger, level: :warning
  config :phoenix, :json_library, JSON

  config :jumon, JumonTest.Endpoint,
    secret_key_base: String.duplicate("jumon-test-secret-key-base-", 4),
    live_view: [signing_salt: "jumon-test-salt"],
    pubsub_server: JumonTest.PubSub,
    render_errors: [formats: [html: JumonTest.ErrorHTML], layout: false],
    server: false

  # The history in the app's database, tested with both adapters. The
  # PostgreSQL tests are tagged :postgres, and run when the database is
  # reachable (see test/test_helper.exs).
  config :jumon, JumonTest.SQLiteRepo,
    database: Path.expand("../tmp/jumon_test.sqlite3", __DIR__),
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: 5

  config :jumon, JumonTest.PostgresRepo,
    url:
      System.get_env("JUMON_TEST_DATABASE_URL", "ecto://postgres:postgres@localhost/jumon_test"),
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: 5

  config :jumon, ecto_repos: [JumonTest.SQLiteRepo, JumonTest.PostgresRepo]
end
