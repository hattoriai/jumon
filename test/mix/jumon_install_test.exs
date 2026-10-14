defmodule Mix.Tasks.Jumon.InstallTest do
  # async: false: the task works in the current working directory.
  use ExUnit.Case, async: false

  alias Mix.Tasks.Jumon.Install

  # The parts of the files of a new Phoenix 1.8 app that the edits read.
  @app_js """
  // Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
  import "phoenix_html"
  // Establish Phoenix Socket and LiveView configuration.
  import {Socket} from "phoenix"
  import {LiveSocket} from "phoenix_live_view"
  import {hooks as colocatedHooks} from "phoenix-colocated/my_app"
  import topbar from "../vendor/topbar"

  const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
  const liveSocket = new LiveSocket("/live", Socket, {
    longPollFallbackMs: 2500,
    params: {_csrf_token: csrfToken},
    hooks: {...colocatedHooks},
  })

  // connect if there are any LiveViews on the page
  liveSocket.connect()
  """

  @app_css """
  /* See the Tailwind configuration guide for advanced usage
     https://tailwindcss.com/docs/configuration */

  @import "tailwindcss" source(none);
  @source "../css";
  @source "../js";
  @source "../../lib/my_app_web";

  /* This file is for your main application CSS */
  """

  @config_exs ~S"""
  import Config

  # Configure esbuild (the version is required)
  config :esbuild,
    version: "0.25.4",
    my_app: [
      args:
        ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
      cd: Path.expand("../assets", __DIR__),
      env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
    ]

  import_config "#{config_env()}.exs"
  """

  # config/config.exs is read for the esbuild note, and never edited.
  @files [
    {@app_js, "assets/js/app.js"},
    {@app_css, "assets/css/app.css"},
    {@config_exs, "config/config.exs"}
  ]

  setup do
    root = Path.join(System.tmp_dir!(), "jumon-install-#{System.unique_integer([:positive])}")

    for {fixture, path} <- @files do
      File.mkdir_p!(Path.dirname(Path.join(root, path)))
      File.write!(Path.join(root, path), fixture)
    end

    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(Mix.Shell.IO)
      File.rm_rf!(root)
    end)

    {:ok, root: root}
  end

  defp run(root, args \\ []) do
    File.cd!(root, fn -> Install.run(args) end)
    messages([])
  end

  defp messages(acc) do
    receive do
      {:mix_shell, :info, [message]} -> messages([message | acc])
    after
      0 -> acc |> Enum.reverse() |> Enum.join("\n")
    end
  end

  defp read(root, path), do: File.read!(Path.join(root, path))

  defp snapshot(root), do: Map.new(@files, fn {_fixture, path} -> {path, read(root, path)} end)

  test "edits the two files and prints the notes", %{root: root} do
    config = read(root, "config/config.exs")
    output = run(root)

    assert read(root, "assets/js/app.js") =~ ~s(import { Jumon } from "jumon")
    assert read(root, "assets/js/app.js") =~ "hooks: {...colocatedHooks, Jumon},"

    assert read(root, "assets/css/app.css") =~
             ~s(@import "../../deps/jumon/priv/static/jumon.css";)

    assert read(root, "assets/css/app.css") =~
             "/* @import \"../../deps/jumon/priv/static/jumon-sumi.css\"; */"

    assert read(root, "config/config.exs") == config

    assert output =~ "* updating assets/js/app.js"
    assert output =~ "* updating assets/css/app.css"
    refute output =~ "config/config.exs"
    assert output =~ "+   hooks: {...colocatedHooks, Jumon},"
    assert output =~ "Your esbuild config sets NODE_PATH to deps/"
    assert output =~ ~s(import { mountJumon } from "jumon")
    assert output =~ "mountJumon()"

    # The commands module of the app (the app of this project is :jumon).
    assert read(root, "lib/jumon_web/commands.ex") =~ "defmodule JumonWeb.Commands do"
    assert read(root, "lib/jumon_web/commands.ex") =~ "use Jumon.Commands"
    assert output =~ "* creating lib/jumon_web/commands.ex"
    assert output =~ "{Jumon.Live, MyAppWeb.Commands}"
  end

  test "a second run changes nothing and says so", %{root: root} do
    run(root)
    before = snapshot(root)

    output = run(root)
    assert snapshot(root) == before
    assert output =~ "Jumon is already installed. Nothing changed."
    assert output =~ "* unchanged assets/js/app.js"
    assert output =~ "* unchanged assets/css/app.css"
    refute output =~ "* updating"
  end

  test "--dry-run prints the diff and writes nothing", %{root: root} do
    before = snapshot(root)
    output = run(root, ["--dry-run"])

    assert snapshot(root) == before
    assert output =~ "* would update assets/js/app.js"
    assert output =~ "--- assets/css/app.css"
    assert output =~ ~s(+ @import "../../deps/jumon/priv/static/jumon.css";)
  end

  test "prints the lines when it cannot edit app.js, and the NODE_PATH line when it is missing",
       %{root: root} do
    File.write!(Path.join(root, "assets/js/app.js"), "console.log(\"custom\")\n")
    File.write!(Path.join(root, "config/config.exs"), "import Config\n")

    output = run(root)

    assert read(root, "assets/js/app.js") == "console.log(\"custom\")\n"
    assert output =~ "* skipping assets/js/app.js"
    assert output =~ ~s(    import { Jumon } from "jumon")

    assert output =~
             ~S|env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}|
  end

  # Mix does not copy a path dependency into deps/, so the imports and the
  # NODE_PATH note must point at the dependency's own directory.
  test "points at the directory of a path dependency", %{root: root} do
    app = Path.join(root, "app")
    File.mkdir_p!(app)
    for dir <- ~w(assets config), do: File.rename!(Path.join(root, dir), Path.join(app, dir))

    install_beside(app)
    output = messages([])

    assert read(app, "assets/css/app.css") =~
             ~s(@import "../../../jumon/priv/static/jumon.css";)

    assert read(app, "assets/css/app.css") =~
             ~s(/* @import "../../../jumon/priv/static/jumon-sumi.css"; */)

    refute read(app, "assets/css/app.css") =~ "deps/jumon"
    refute output =~ "Your esbuild config sets NODE_PATH to deps/"
    assert output =~ "Jumon is a path dependency (../jumon), so it is not in deps/."
    assert output =~ ~S|Path.expand("../..", __DIR__),|

    # Once NODE_PATH has the directory, the note says the import resolves.
    config = read(app, "config/config.exs")

    File.write!(
      Path.join(app, "config/config.exs"),
      String.replace(
        config,
        ~S|Path.expand("../deps", __DIR__),|,
        ~S|Path.expand("../deps", __DIR__), Path.expand("../..", __DIR__),|
      )
    )

    File.write!(Path.join(app, "assets/css/app.css"), @app_css)
    install_beside(app)
    assert messages([]) =~ "has the directory of the Jumon path dependency in NODE_PATH"
  end

  # The package beside the app, as Mix gives a path dependency: expanded
  # from the working directory (the temporary directory can be a symbolic
  # link, as on macOS).
  defp install_beside(app) do
    File.cd!(app, fn -> Install.install([], Path.expand("../jumon")) end)
  end

  # An umbrella child keeps its Hex dependencies in the deps directory of
  # the umbrella, ../../deps: Jumon there is not a path dependency.
  test "follows the deps directory of an umbrella child", %{root: root} do
    app = Path.join(root, "apps/web")
    File.mkdir_p!(app)
    for dir <- ~w(assets config), do: File.rename!(Path.join(root, dir), Path.join(app, dir))

    install_umbrella_child(app)
    output = messages([])

    assert read(app, "assets/css/app.css") =~
             ~s(@import "../../../../deps/jumon/priv/static/jumon.css";)

    refute output =~ "path dependency"
    assert output =~ "must resolve `jumon` from ../../deps/."
    assert output =~ ~S|Path.expand("../../../deps", __DIR__)|

    config = read(app, "config/config.exs")

    File.write!(
      Path.join(app, "config/config.exs"),
      String.replace(
        config,
        ~S|Path.expand("../deps", __DIR__)|,
        ~S|Path.expand("../../../deps", __DIR__)|
      )
    )

    File.write!(Path.join(app, "assets/css/app.css"), @app_css)
    install_umbrella_child(app)
    assert messages([]) =~ "Your esbuild config sets NODE_PATH to ../../deps/, so"
  end

  defp install_umbrella_child(app) do
    File.cd!(app, fn -> Install.install([], Path.expand("../../deps/jumon"), "../../deps") end)
  end

  test "follows MIX_DEPS_PATH", %{root: root} do
    System.put_env("MIX_DEPS_PATH", "vendor/deps")
    output = try do: run(root), after: System.delete_env("MIX_DEPS_PATH")

    assert read(root, "assets/css/app.css") =~
             ~s(@import "../../vendor/deps/jumon/priv/static/jumon.css";)

    refute output =~ "path dependency"
    assert output =~ ~S|Path.expand("../vendor/deps", __DIR__)|
  end

  test "package_path/2 reads the path of the dependency", %{root: root} do
    File.cd!(root, fn ->
      assert Install.package_path(%{}) == Path.join(File.cwd!(), "deps/jumon")
      assert Install.package_path(%{}, "../../deps") == Path.expand("../../deps/jumon")
      assert Install.package_path(%{jumon: "../jumon"}) == Path.expand("../jumon")
    end)
  end

  test "says what to add for a file that is not there", %{root: root} do
    File.rm!(Path.join(root, "assets/css/app.css"))
    output = run(root)

    refute File.exists?(Path.join(root, "assets/css/app.css"))
    assert output =~ "* skipping assets/css/app.css (not found)"
    assert output =~ ~s(@import "../../deps/jumon/priv/static/jumon.css";)
  end
end
