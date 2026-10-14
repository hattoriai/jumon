defmodule Mix.Tasks.Jumon.BuildTest do
  # Builds the real bundles into priv/static, so it does not run in parallel
  # with other tests. It needs npm (and the network for the first `npm ci`),
  # so it runs only with `mix test --include build`.
  use ExUnit.Case, async: false

  @root Path.expand("../..", __DIR__)
  @static Path.join(@root, "priv/static")
  @files ~w(jumon.esm.js jumon.cjs.js jumon.css jumon-sumi.css)
  @exports ~w(Jumon mountJumon)

  @moduletag :build
  @moduletag timeout: 600_000

  unless System.find_executable("npm") do
    @moduletag skip: "npm is not on the path, so mix jumon.build cannot run"
  end

  setup_all do
    # Files from an earlier build must not make the test pass, and a stray
    # file must be gone after the build.
    for file <- @files, do: File.rm(Path.join(@static, file))
    File.mkdir_p!(Path.join(@static, "stray"))
    File.write!(Path.join(@static, "stray/leftover.js"), "")

    mix = System.find_executable("mix") || flunk("mix is not on the path")

    {output, status} =
      System.cmd(mix, ["jumon.build"],
        cd: @root,
        env: [{"MIX_ENV", "dev"}],
        stderr_to_stdout: true
      )

    %{output: output, status: status}
  end

  test "mix jumon.build writes the bundles and the style sheets", %{
    output: output,
    status: status
  } do
    assert status == 0, "mix jumon.build failed:\n" <> output

    for file <- @files do
      path = Path.join(@static, file)
      assert File.regular?(path), "#{file} is missing"
      assert File.stat!(path).size > 0, "#{file} is empty"
    end
  end

  test "priv/static holds only the four files of the package" do
    assert @static |> File.ls!() |> Enum.sort() == Enum.sort(@files)
  end

  test "the ESM bundle exports the hook and mountJumon" do
    esm = File.read!(Path.join(@static, "jumon.esm.js"))
    [exports] = Regex.run(~r/export\{([^}]*)\}/, esm, capture: :all_but_first)
    names = exports |> String.split(",") |> Enum.map(&(&1 |> String.split(" as ") |> List.last()))

    for name <- @exports, do: assert(name in names, "jumon.esm.js does not export #{name}")
  end

  describe "mix hex.build" do
    @describetag :tmp_dir

    test "packages the bundles and the guides, and no development files", %{tmp_dir: tmp_dir} do
      mix = System.find_executable("mix")
      out = Path.join(tmp_dir, "package")

      {output, status} =
        System.cmd(mix, ["hex.build", "--unpack", "--output", out],
          cd: @root,
          env: [{"MIX_ENV", "dev"}],
          stderr_to_stdout: true
        )

      assert status == 0, "mix hex.build failed:\n" <> output

      files =
        out
        |> Path.join("**")
        |> Path.wildcard(match_dot: true)
        |> Enum.filter(&File.regular?/1)
        |> Enum.map(&Path.relative_to(&1, out))

      for file <- @files do
        assert "priv/static/#{file}" in files, "the package has no priv/static/#{file}"
      end

      assert files |> Enum.filter(&String.starts_with?(&1, "priv/")) |> Enum.sort() ==
               @files |> Enum.map(&"priv/static/#{&1}") |> Enum.sort()

      guides =
        @root
        |> Path.join("guides/*.md")
        |> Path.wildcard()
        |> Enum.map(&Path.relative_to(&1, @root))

      assert guides != []
      for guide <- guides, do: assert(guide in files, "the package has no #{guide}")

      for file <- files, prefix <- ~w(tmp/ dev/ e2e/ test/ assets/ deps/ _build/ doc/) do
        refute String.starts_with?(file, prefix), "the package has #{file}"
      end

      refute "dev.exs" in files
    end
  end

  describe "the CJS bundle" do
    if System.find_executable("node") == nil do
      @describetag skip: "node is not on the path, so the CJS bundle cannot be required"
    end

    test "require() of the package entry point gives the hook and mountJumon" do
      script = """
      const jumon = require("./priv/static/jumon.cjs.js");
      process.stdout.write(JSON.stringify(Object.keys(jumon).sort()));
      """

      {output, status} = System.cmd("node", ["-e", script], cd: @root, stderr_to_stdout: true)

      assert status == 0, "node could not require jumon.cjs.js:\n" <> output
      assert JSON.decode!(output) == @exports
    end
  end
end

defmodule Mix.Tasks.Jumon.OwnProjectTest do
  # Mix.Project.in_project/4 changes the current Mix project for the whole
  # VM, so this module does not run in parallel with other tests.
  use ExUnit.Case, async: false

  alias Mix.Tasks.Jumon.{Build, ReleaseCheck}

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    File.write!(Path.join(tmp_dir, "mix.exs"), """
    defmodule JumonHostApp.MixProject do
      use Mix.Project
      def project, do: [app: :jumon_host_app, version: "1.0.0"]
    end
    """)

    static = Path.join(tmp_dir, "priv/static")
    File.mkdir_p!(static)
    robots = Path.join(static, "robots.txt")
    File.write!(robots, "User-agent: *")

    %{robots: robots}
  end

  test "the guards accept only the Jumon project" do
    assert Build.ensure_jumon!(app: :jumon) == :ok
    assert ReleaseCheck.ensure_jumon!(app: :jumon) == :ok

    assert_raise Mix.Error, ~r/^mix jumon.build is for work on Jumon itself/, fn ->
      Build.ensure_jumon!(app: :my_app)
    end

    assert_raise Mix.Error, ~r/^mix jumon.release_check is for work on Jumon itself/, fn ->
      ReleaseCheck.ensure_jumon!(app: :my_app)
    end
  end

  test "mix jumon.build stops in an application and keeps its priv/static", %{
    tmp_dir: tmp_dir,
    robots: robots
  } do
    Mix.Project.in_project(:jumon_host_app, tmp_dir, fn _module ->
      assert_raise Mix.Error, ~r/an app gets the built files in the Hex package/, fn ->
        Build.run([])
      end
    end)

    assert File.read!(robots) == "User-agent: *"
  end

  test "mix jumon.release_check stops in an application", %{tmp_dir: tmp_dir} do
    Mix.Project.in_project(:jumon_host_app, tmp_dir, fn _module ->
      assert_raise Mix.Error, ~r/checks the files of a Jumon release/, fn ->
        ReleaseCheck.run([])
      end
    end)
  end
end
