defmodule Mix.Tasks.Jumon.Build do
  @shortdoc "Builds the palette bundles and the style sheets into priv/static"

  @moduledoc """
  Builds the Jumon palette into `priv/static`.

      $ mix jumon.build

  This task is for work on Jumon itself. An application that uses Jumon
  gets the built files in the Hex package and does not run this task: in
  any project but Jumon, the task stops with an error before it changes
  a file.

  The task:

    1. Runs `npm ci` in `assets/` when `assets/node_modules` is missing or
       `assets/package-lock.json` changed since the last install.
    2. Empties `priv/static`, so that it holds only the files of this
       build.
    3. Runs esbuild (the `esbuild` Mix package) with the `:jumon_esm` and
       `:jumon_cjs` profiles.
    4. Copies `assets/css/jumon.css` and `assets/css/jumon-sumi.css` to
       `priv/static/`.

  After the task, `priv/static` holds exactly these four files, which are
  the files of the Hex package.

  It needs `npm` on the path and the `:esbuild` dependency, which is
  available in the `:dev` environment.
  """

  use Mix.Task

  @compile {:no_warn_undefined, Esbuild}

  @assets "assets"
  @static "priv/static"
  @lock_hash "node_modules/.jumon-lock-sha256"
  @profiles [:jumon_esm, :jumon_cjs]
  @stylesheets ["jumon.css", "jumon-sumi.css"]

  @impl Mix.Task
  def run(_args) do
    ensure_jumon!(Mix.Project.config())
    Mix.Task.run("loadpaths")

    unless Code.ensure_loaded?(Esbuild) do
      Mix.raise("""
      mix jumon.build needs the :esbuild dependency, which is available in \
      the :dev environment. Run it as `MIX_ENV=dev mix jumon.build`.\
      """)
    end

    {:ok, _apps} = Application.ensure_all_started(:esbuild)

    install_packages()
    File.rm_rf!(@static)
    File.mkdir_p!(@static)
    Enum.each(@profiles, &bundle/1)
    Enum.each(@stylesheets, &copy_stylesheet/1)

    Mix.shell().info("Jumon assets are in #{@static}/")
  end

  # The task empties priv/static, so it must never run in an application.
  @doc false
  @spec ensure_jumon!(keyword()) :: :ok
  def ensure_jumon!(config) do
    if config[:app] == :jumon do
      :ok
    else
      Mix.raise(
        "mix jumon.build is for work on Jumon itself; an app gets the built files in the Hex package"
      )
    end
  end

  defp install_packages do
    lock = Path.join(@assets, "package-lock.json")
    stamp = Path.join(@assets, @lock_hash)
    hash = lock |> File.read!() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)

    if File.dir?(Path.join(@assets, "node_modules")) and File.read(stamp) == {:ok, hash} do
      Mix.shell().info("assets/node_modules is up to date")
    else
      npm = System.find_executable("npm") || Mix.raise("mix jumon.build needs npm on the path")
      Mix.shell().info("Running npm ci in assets/")

      case System.cmd(npm, ["ci", "--prefix", @assets], into: IO.stream(), stderr_to_stdout: true) do
        {_output, 0} -> File.write!(stamp, hash)
        {_output, status} -> Mix.raise("npm ci exited with status #{status}")
      end
    end
  end

  defp bundle(profile) do
    case Esbuild.install_and_run(profile, []) do
      0 -> :ok
      status -> Mix.raise("esbuild #{profile} exited with status #{status}")
    end
  end

  defp copy_stylesheet(name) do
    File.cp!(Path.join([@assets, "css", name]), Path.join(@static, name))
  end
end
