defmodule Mix.Tasks.Jumon.ReleaseCheck do
  @shortdoc "Checks that priv/static holds the four bundle files and nothing else"

  @moduledoc """
  Checks the built files before a release of Jumon.

      $ mix jumon.release_check

  This task is for work on Jumon itself; the `release` alias runs it
  after `mix jumon.build` and before `mix hex.publish`. In any project
  but Jumon, it stops with an error. It fails when:

    * one of the four bundle files (`jumon.esm.js`, `jumon.cjs.js`,
      `jumon.css` and `jumon-sumi.css`) is missing from `priv/static`,
      or is empty (the empty files that CI makes are not a build);
    * `priv/static` holds any other file or directory;
    * the `version` of `package.json` is not the version of `mix.exs`.
  """

  use Mix.Task

  @static "priv/static"
  @files ~w(jumon.esm.js jumon.cjs.js jumon.css jumon-sumi.css)

  @impl Mix.Task
  def run(_args) do
    config = Mix.Project.config()
    ensure_jumon!(config)
    version = config[:version]

    case check(@static, "package.json", version) do
      :ok ->
        Mix.shell().info(
          "#{@static} holds the four bundle files, and nothing else, and package.json has version #{version}"
        )

      {:error, problems} ->
        Mix.raise("""
        Jumon is not ready for a release:

        #{Enum.map_join(problems, "\n", &("  * " <> &1))}

        Build with `mix jumon.build` (it empties #{@static} first); keep the \
        version of package.json equal to the version of mix.exs.\
        """)
    end
  end

  @doc false
  @spec ensure_jumon!(keyword()) :: :ok
  def ensure_jumon!(config) do
    if config[:app] == :jumon do
      :ok
    else
      Mix.raise(
        "mix jumon.release_check is for work on Jumon itself; it checks the files of a Jumon release"
      )
    end
  end

  @doc false
  @spec check(Path.t(), Path.t(), String.t()) :: :ok | {:error, [String.t()]}
  def check(static, package_json, version) do
    entries =
      case File.ls(static) do
        {:ok, entries} -> entries
        {:error, _reason} -> []
      end

    problems =
      Enum.flat_map(@files, &bundle_problems(static, &1, entries)) ++
        Enum.map(Enum.sort(entries -- @files), &"#{static}/#{&1} is not a bundle file") ++
        version_problems(package_json, version)

    if problems == [], do: :ok, else: {:error, problems}
  end

  defp bundle_problems(static, file, entries) do
    path = Path.join(static, file)

    cond do
      file not in entries -> ["#{path} is missing"]
      not File.regular?(path) -> ["#{path} is not a file"]
      File.stat!(path).size == 0 -> ["#{path} is empty"]
      true -> []
    end
  end

  defp version_problems(package_json, version) do
    with {:ok, source} <- File.read(package_json),
         {:ok, %{"version" => ^version}} <- JSON.decode(source) do
      []
    else
      _other -> ["the version of #{package_json} is not #{version}"]
    end
  end
end
