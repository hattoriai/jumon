defmodule Jumon.LiveTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Jumon.Test

  alias Jumon.History.Memory

  @endpoint JumonTest.Endpoint

  setup do
    {:ok, conn: Plug.Test.init_test_session(build_conn(), %{})}
  end

  test "the palette has the actions of the commands, each with its children", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    ids = view |> actions() |> Enum.map(& &1["id"])

    assert ["home", "settings", "new_issue", "theme", "light", "dark" | _] = ids
    assert "greet" in ids
    assert Enum.find(actions(view), &(&1["id"] == "greet"))["name"] == "Greet Ada"
    assert Enum.find(actions(view), &(&1["id"] == "dark"))["parent"] == "theme"
  end

  test "search: the actions, ranked, then the sources", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert names(search(view, "set")) |> Enum.take(2) == ["Settings", "Set priority…"]
    assert "Dark" in names(search(view, "dark"))
    refute "Dark" in names(search(view, ""))

    results = search(view, "the")

    assert ["Fix the login form", "Ship the palette", "Write the guides"] ==
             results |> Enum.filter(&(&1["source"] == "issues")) |> names()

    assert %{"id" => "issues:2", "perform" => %{"type" => "navigate", "to" => "/issues/2"}} =
             Enum.find(results, &(&1["name"] == "Ship the palette"))

    # The async source answers later, with its ref.
    assert ["Ada Lovelace"] ==
             view |> search("ada") |> Enum.filter(&(&1["source"] == "people")) |> names()
  end

  test "an action runs on the server", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert %{"ok" => true} = run(view, :greet)
    assert render(view) =~ "greeted=true"

    assert %{"ok" => true} = run(view, :archive)
    assert render(view) =~ "archived=true"
  end

  test "the server checks what it runs", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert %{"error" => "unknown"} = run(view, "nope")
    assert %{"error" => "unknown"} = run(view, :home)
    assert %{"error" => "disabled"} = run(view, :locked)
    assert %{"error" => "forbidden"} = run(view, :forbidden)
    assert %{"error" => "message", "message" => "Not today"} = run(view, :fail)
  end

  test "arguments: a value is one the server offered", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert %{"error" => "invalid", "arg" => "person"} = run(view, :assign, %{person: "ada"})

    assert [%{"id" => "ada", "name" => "Ada Lovelace"}] =
             search_arg(view, :assign, :person, "ada")

    assert %{"error" => "invalid", "arg" => "note"} =
             run(view, :assign, %{person: "ada", note: String.duplicate("x", 21)})

    assert %{"ok" => true} = run(view, :assign, %{person: "ada", note: "soon"})
    assert render(view) =~ ~s(assigned={&quot;ada&quot;, &quot;soon&quot;})

    assert %{"error" => "invalid"} = run(view, :priority, %{level: "urgent"})
    assert %{"ok" => true} = run(view, :priority, %{level: "high"})
    assert render(view) =~ ~s(priority=&quot;high&quot;)
  end

  test "the actions of a page, and of the results of a search", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/issues/2")
    assert "Close issue 2" in names(search(view, "close"))
    assert %{"ok" => true} = run(view, :close_issue)
    assert render(view) =~ ~s(closed=&quot;2&quot;)

    # A secondary action of a result is the server's to run only once offered.
    assert %{"error" => "unknown"} = run(view, "issues:2/copy_key")
  end

  test "open and close from the server", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    render_hook(view, "open_palette", %{})
    assert_push_event(view, "jumon:open", %{"query" => "set"})
  end

  test "the history on the server", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/server")
    assert Enum.find(actions(view), &(&1["id"] == "ping"))
    assert %{"ok" => true} = run(view, :ping)

    render_hook(element(view, "#jumon"), "jumon:used", %{"id" => "home", "ref" => 1})
    render_hook(element(view, "#jumon"), "jumon:used", %{"id" => "home", "ref" => 2})
    render_hook(element(view, "#jumon"), "jumon:recent", %{"ref" => 3})
    %{proxy: {proxy, _topic, _pid}} = view
    assert_receive {^proxy, {:reply, %{"ref" => 3, "items" => [home, ping]}}}
    assert {home["id"], ping["id"]} == {"home", "ping"}
    assert home["action"]["name"] == "Home"

    render_hook(element(view, "#jumon"), "jumon:forget", %{"id" => "home", "ref" => 4})
    assert [%{id: "ping"}] = Memory.recent([name: JumonTest.History], 7, 10)
  end

  test "a LiveView without the hook has no palette" do
    assert_raise ArgumentError, ~r/no palette/, fn ->
      Jumon.Live.put_actions(%Phoenix.LiveView.Socket{}, [])
    end
  end
end
