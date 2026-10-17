defmodule Mix.Tasks.Jumon.Install do
  @shortdoc "Adds the Jumon hook and style sheet to a Phoenix app"

  @moduledoc """
  Sets up Jumon in a Phoenix application.

      $ mix jumon.install
      $ mix jumon.install --dry-run

  The task edits two files, and writes a third when it is missing:

    * `assets/js/app.js` - adds `import { Jumon } from "jumon"` and puts
      `Jumon` in the `hooks` of the `LiveSocket`. When it cannot find the
      `new LiveSocket(...)` call, or its hooks are not an object or a
      variable, it changes nothing and prints the lines to add.
    * `assets/css/app.css` - adds
      `@import "../../deps/jumon/priv/static/jumon.css";`, and the Sumi
      theme import as a comment. The imports follow the deps directory of
      the project (`Mix.Project.deps_path/0`) when it is not `deps/`, as in
      an umbrella child or with `MIX_DEPS_PATH`. For a path dependency
      (`{:jumon, path: "../jumon"}`), which Mix does not copy into
      `deps/`, the imports point at the dependency's directory instead.

    * `lib/my_app_web/commands.ex` - a commands module (`MyAppWeb.Commands`,
      see `Jumon.Commands`) with a first action, when the file is missing.

  Then it prints the esbuild note (the app's esbuild must resolve `jumon`
  through `NODE_PATH`: from `deps/`, or, for a path dependency, from the
  directory that holds it) and how to start the palette on a page without
  LiveView.

  The task is idempotent: it does not add what a file already has, and when
  there is nothing to add it says so.

  ## Options

    * `--dry-run` - prints the changes as a diff and writes nothing.
  """

  use Mix.Task

  alias Jumon.Install.Edits

  @js "assets/js/app.js"
  @css "assets/css/app.css"
  @config "config/config.exs"

  @impl Mix.Task
  def run(argv) do
    deps_path = Mix.Project.deps_path()
    install(argv, package_path(Mix.Project.deps_paths(), deps_path), deps_path)
  end

  @doc false
  # The task, with the directory of the Jumon package and the deps
  # directory of the project given.
  @spec install([String.t()], Path.t(), Path.t()) :: :ok
  def install(argv, package, deps_path \\ "deps") do
    {opts, _args} = OptionParser.parse!(argv, strict: [dry_run: :boolean])
    dry_run? = Keyword.get(opts, :dry_run, false)

    css_dir = Edits.relative(package, Path.dirname(@css))

    results = [
      edit(@js, &Edits.app_js/1, Edits.app_js_manual(), dry_run?),
      edit(@css, &Edits.app_css(&1, css_dir), Edits.app_css_manual(css_dir), dry_run?),
      commands(Mix.Project.config()[:app], dry_run?)
    ]

    if Enum.all?(results, &(&1 == :unchanged)) do
      Mix.shell().info("Jumon is already installed. Nothing changed.")
    else
      notes(package, deps_path)
    end
  end

  @doc false
  # Where the Jumon package is, from `Mix.Project.deps_paths/0`: jumon in
  # the deps directory (`Mix.Project.deps_path/0`, which an umbrella child or
  # MIX_DEPS_PATH moves away from deps/), or the directory of a path
  # dependency (`{:jumon, path: "../jumon"}`), which Mix does not copy there.
  @spec package_path(%{optional(atom()) => Path.t()}, Path.t()) :: Path.t()
  def package_path(deps_paths, deps_path \\ "deps") do
    case deps_paths[:jumon] do
      nil -> Path.expand(Path.join(deps_path, "jumon"))
      path -> Path.expand(path)
    end
  end

  @doc false
  # The commands module of the app, written when its file is missing.
  @spec commands(atom() | nil, boolean()) :: :changed | :unchanged
  def commands(nil, _dry_run?), do: :unchanged

  def commands(app, dry_run?) do
    web = Edits.web_module(app)
    path = Path.join(["lib", Macro.underscore(web), "commands.ex"])

    cond do
      File.exists?(path) ->
        Mix.shell().info([:green, "* unchanged ", :reset, path, " (it exists)"])
        :unchanged

      dry_run? ->
        Mix.shell().info([:cyan, "* would create ", :reset, path])
        :changed

      true ->
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, Edits.commands_module(web))
        Mix.shell().info([:green, "* creating ", :reset, path])
        :changed
    end
  end

  defp edit(path, fun, manual, dry_run?) do
    case File.read(path) do
      {:ok, source} ->
        apply_edit(path, source, fun.(source), dry_run?)

      {:error, _reason} ->
        Mix.shell().info([:yellow, "* skipping ", :reset, path, " (not found)"])
        Mix.shell().info(indent(manual))
        :manual
    end
  end

  defp apply_edit(path, _source, :unchanged, _dry_run?) do
    Mix.shell().info([:green, "* unchanged ", :reset, path, " (Jumon is already there)"])
    :unchanged
  end

  defp apply_edit(path, _source, {:manual, text}, _dry_run?) do
    Mix.shell().info([:yellow, "* skipping ", :reset, path, " (add the lines below by hand)"])
    Mix.shell().info(indent(text))
    :manual
  end

  defp apply_edit(path, source, {:changed, new}, true) do
    Mix.shell().info([:cyan, "* would update ", :reset, path])
    Mix.shell().info(Edits.diff(path, source, new))
    :changed
  end

  defp apply_edit(path, source, {:changed, new}, false) do
    File.write!(path, new)
    Mix.shell().info([:green, "* updating ", :reset, path])
    Mix.shell().info(Edits.diff(path, source, new))
    :changed
  end

  defp notes(package, deps_path) do
    config_source =
      case File.read(@config) do
        {:ok, source} -> source
        {:error, _reason} -> ""
      end

    Mix.shell().info("""

    #{esbuild_note(config_source, package, deps_path)}

    Then mount the commands in the live_session of your router, after the
    hooks that assign what they read:

        live_session :default,
          on_mount: [{MyAppWeb.UserAuth, :mount_current_scope}, {Jumon.Live, MyAppWeb.Commands}] do

    and render the palette in your layout (lib/my_app_web/components/layouts.ex),
    with @jumon passed on to it (<Layouts.app flash={@flash} jumon={@jumon}>),
    or, in a Phoenix 1.7 app, in layouts/app.html.heex:

        <Jumon.Components.command_palette jumon={@jumon}>
          <:icon :let={name}><.icon name={name} class="size-4" /></:icon>
        </Jumon.Components.command_palette>

    For the Sumi theme, remove the comment marks around the jumon-sumi.css
    import in assets/css/app.css. For a history of each person in your
    database, see `mix jumon.gen.migration`.

    On a page without LiveView, the hook does not run. Import mountJumon
    in the page's script and call it after the page loads:

        import { mountJumon } from "jumon"

        window.addEventListener("DOMContentLoaded", () => mountJumon())
    """)
  end

  defp esbuild_note(config_source, package, deps_path) do
    if Path.dirname(package) == Path.expand(deps_path) do
      deps = Edits.relative(deps_path, ".")
      from_config = Edits.relative(deps_path, "config")

      resolves? =
        if deps == "deps",
          do: Edits.node_path?(config_source),
          else: Edits.node_path?(config_source, from_config)

      if resolves? do
        "Your esbuild config sets NODE_PATH to #{deps}/, so `import { Jumon } from \"jumon\"` resolves."
      else
        """
        The esbuild profile of your app must resolve `jumon` from #{deps}/. Give it
        NODE_PATH=#{deps} in config/config.exs:

            env: %{"NODE_PATH" => [Path.expand("#{from_config}", __DIR__), Mix.Project.build_path()]}\
        """
      end
    else
      parent = Edits.relative(Path.dirname(package), "config")

      if Edits.node_path?(config_source, parent) do
        "Your esbuild config has the directory of the Jumon path dependency in NODE_PATH, so `import { Jumon } from \"jumon\"` resolves."
      else
        """
        Jumon is a path dependency (#{Edits.relative(package, ".")}), so it is not in deps/.
        The esbuild profile of your app finds `jumon` through NODE_PATH: add the
        directory that holds it to the NODE_PATH in config/config.exs:

            env: %{
              "NODE_PATH" => [
                Path.expand("../deps", __DIR__),
                Path.expand("#{parent}", __DIR__),
                Mix.Project.build_path()
              ]
            }\
        """
      end
    end
  end

  defp indent(text) do
    text
    |> String.trim_trailing()
    |> String.split("\n")
    |> Enum.map_join("\n", fn
      "" -> ""
      line -> "    " <> line
    end)
  end
end
