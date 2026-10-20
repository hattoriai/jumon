defmodule Jumon.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/hattoriai/jumon"

  # JUMON_OLDEST=1 resolves the oldest Phoenix and LiveView that Jumon
  # supports, for the CI job that tests them.
  @oldest System.get_env("JUMON_OLDEST") in ["1", "true"]

  def project do
    [
      app: :jumon,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      test_ignore_filters: [&String.starts_with?(&1, "test/fixtures/")],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      # For the code reloader of the development server (dev.exs). The
      # listener is Phoenix 1.8's, so the oldest versions go without it.
      listeners: if(@oldest, do: [], else: [Phoenix.CodeReloader]),
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit, :esbuild, :ecto, :ecto_sql],
        plt_core_path: "priv/plts",
        plt_file: {:no_warn, "priv/plts/project.plt"},
        ignore_warnings: ".dialyzer_ignore.exs"
      ],
      package: package(),
      docs: docs(),
      description: description(),
      name: "Jumon",
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  def cli do
    [preferred_envs: [precommit: :test]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:bandit, "~> 1.5", only: :dev},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      # The history of each person in the app's database (Jumon.History.Ecto)
      # needs Ecto SQL and one of its adapters; the rest of Jumon does not.
      {:ecto, "~> 3.13", optional: true},
      {:ecto_sql, "~> 3.13", optional: true},
      {:ecto_sqlite3, "~> 0.22", only: [:dev, :test]},
      {:esbuild, "~> 0.10", only: :dev, runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:lazy_html, "~> 0.1", only: :test},
      {:phoenix, if(@oldest, do: "~> 1.7.14", else: "~> 1.7.14 or ~> 1.8")},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.6", only: :dev},
      {:phoenix_live_view, if(@oldest, do: "~> 1.1.0", else: "~> 1.1")},
      {:postgrex, "~> 0.19", only: [:dev, :test]},
      {:stream_data, "~> 1.1", only: :test},
      {:telemetry, "~> 1.0"}
    ]
  end

  defp description do
    "Commands for Phoenix: a command palette for LiveView, with actions on the server, search as you type, shortcuts and a history of what each person runs."
  end

  defp package do
    [
      name: "jumon",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      # The bundle files by name: other build output in priv/static never
      # goes into the package.
      files: ~w(
        lib
        priv/static/jumon.esm.js
        priv/static/jumon.cjs.js
        priv/static/jumon.css
        priv/static/jumon-sumi.css
        package.json
        mix.exs
        .formatter.exs
        guides
        README.md
        CHANGELOG.md
        LICENSE
        NOTICE
      )
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      # The banner of the README, at the same relative path in the docs.
      assets: %{"media" => "media"},
      extras: [
        "README.md",
        "guides/quickstart.md",
        "guides/actions.md",
        "guides/searching.md",
        "guides/arguments.md",
        "guides/shortcuts.md",
        "guides/history.md",
        "guides/pages.md",
        "guides/testing.md",
        "guides/theming.md",
        "guides/accessibility.md",
        "guides/limits.md",
        "CHANGELOG.md",
        "CONTRIBUTING.md",
        "SECURITY.md"
      ],
      groups_for_extras: [
        Guides: [
          "guides/quickstart.md",
          "guides/actions.md",
          "guides/searching.md",
          "guides/arguments.md",
          "guides/shortcuts.md",
          "guides/history.md",
          "guides/pages.md",
          "guides/testing.md",
          "guides/theming.md"
        ],
        Reference: [
          "guides/accessibility.md",
          "guides/limits.md"
        ]
      ],
      groups_for_modules: [
        Palette: [Jumon, Jumon.Components, Jumon.Live, Jumon.Messages],
        Actions: [Jumon.Commands, Jumon.Action, Jumon.Arg, Jumon.Source, Jumon.Match],
        History: [Jumon.History, Jumon.History.Memory, Jumon.History.Ecto, Jumon.Migration],
        Testing: [Jumon.Test]
      ]
    ]
  end

  # The browser tests need their npm packages; `npm ci` runs once.
  defp e2e_deps(_args) do
    unless File.dir?("e2e/node_modules") do
      Mix.Task.run("cmd", ~w(--cd e2e npm ci))
    end
  end

  defp aliases do
    [
      "assets.build": ["jumon.build"],
      dev: "run --no-halt dev.exs",
      "test.e2e": [&e2e_deps/1, "cmd --cd e2e npm test"],
      "test.js": ["cmd --cd assets npm test"],
      # The compile and the asset build run in a child VM, as in Kotoba and
      # Koyomi: once anything compiles in this VM, Mix no longer finds the
      # tasks of the Hex archive. The check refuses a priv/static with
      # anything but the bundle files.
      release: [
        "cmd mix jumon.build",
        "cmd mix jumon.release_check",
        "hex.publish --yes",
        "cmd git tag v#{@version} -f",
        "cmd git push",
        "cmd git push --tags"
      ],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "credo --strict",
        "test"
      ]
    ]
  end
end
