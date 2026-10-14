defmodule Mix.Tasks.Jumon.Gen.MigrationTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Jumon.Gen.Migration

  test "the migration calls Jumon.Migration" do
    source = Migration.migration(MyApp.Repo, nil)
    assert source =~ "defmodule MyApp.Repo.Migrations.AddJumonHistory do"
    assert source =~ "def up, do: Jumon.Migration.up(version: 1)"

    assert Migration.migration(MyApp.Repo, "app") =~
             ~s{Jumon.Migration.down(version: 1, prefix: "app")}

    assert {_ast, []} = Code.string_to_quoted_with_comments!(source) |> then(&{&1, []})
  end
end
