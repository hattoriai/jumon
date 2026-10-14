defmodule Jumon.ActionTest do
  use ExUnit.Case, async: true

  alias Jumon.Action
  alias Phoenix.LiveView.JS

  defp perform(opts), do: Action.to_client(Jumon.action(:a, "A", opts))["perform"]

  test "an action as the browser reads it, without functions" do
    action =
      Jumon.action(:assign, "Assign to…",
        section: "Issues",
        shortcut: ["Mod+Shift+A", "a"],
        args: [person: [search: fn _query -> [] end]],
        run: fn _args, socket -> socket end,
        actions: [Jumon.action(:copy, "Copy", copy: "x")]
      )

    client = Action.to_client(action)
    assert client["id"] == "assign"
    assert client["perform"] == %{"type" => "server"}
    assert client["shortcut"] == ["mod+shift+a", "a"]
    assert [%{"name" => "person", "type" => "search", "label" => "Person"}] = client["args"]
    assert [%{"id" => "assign/copy", "parent" => "assign"}] = client["actions"]
    refute Map.has_key?(client, "priority")
    refute inspect(client) =~ "Function"
  end

  test "what an action does, in the browser's form" do
    assert perform(navigate: "/x", replace: true) == %{
             "type" => "navigate",
             "to" => "/x",
             "replace" => true
           }

    assert perform(patch: "/x") == %{"type" => "patch", "to" => "/x", "replace" => false}

    assert perform(href: "/log-out", method: :delete) ==
             %{"type" => "href", "to" => "/log-out", "method" => "delete"}

    assert perform(href: "https://hex.pm", target: "_blank") ==
             %{"type" => "href", "to" => "https://hex.pm", "target" => "_blank"}

    assert perform(event: "save", value: %{id: 1}) ==
             %{"type" => "event", "event" => "save", "value" => %{id: 1}}

    assert perform(copy: "WEB-1") == %{"type" => "copy", "text" => "WEB-1"}
    assert %{"type" => "js", "js" => js} = perform(js: JS.dispatch("app:theme"))
    assert [["dispatch", %{"event" => "app:theme"}]] = JSON.decode!(js)
  end

  test "icons: a name or classes of the app, or an emoji" do
    assert Jumon.action(:a, "A", icon: "hero-home").icon == "hero-home"
    assert Jumon.action(:a, "A", icon: "fa-solid fa-house").icon == "fa-solid fa-house"
    action = Jumon.action(:a, "A", icon: "🚀")
    assert {action.icon, action.glyph} == {nil, "🚀"}
    assert Jumon.action(:a, "A", glyph: "§").glyph == "§"
    assert_raise ArgumentError, ~r/:icon/, fn -> Jumon.action(:a, "A", icon: "<svg>") end
  end

  test "children are flattened with their parent" do
    action =
      Jumon.action(:theme, "Theme",
        children: [
          Jumon.action(:light, "Light", copy: "l"),
          Jumon.action(:dark, "Dark", copy: "d")
        ]
      )

    assert [{"theme", nil}, {"light", "theme"}, {"dark", "theme"}] =
             action |> Action.flatten() |> Enum.map(&{&1.id, &1.parent})
  end

  test "items of a search: actions, maps and tuples" do
    assert %Action{id: "1", name: "One"} = Action.coerce({1, "One"})

    assert %Action{id: "2", name: "Two", subtitle: "S", perform: {:navigate, "/2", []}} =
             Action.coerce(%{
               "id" => 2,
               "label" => "Two",
               "subtitle" => "S",
               "navigate" => "/2",
               "other" => 1
             })

    assert Action.coerce(%{id: 3}) == nil
    assert Action.coerce(:nope) == nil
    assert Action.coerce(%{id: 4, name: "Bad", navigate: "javascript:alert(1)"}) == nil
  end

  test "refuses what is not valid" do
    for {opts, message} <- [
          {[nope: 1], ~r/unknown option :nope/},
          {[navigate: "/a", copy: "b"], ~r/one thing/},
          {[navigate: "https://evil.example"], ~r/must start with one "\/"/},
          {[href: "javascript:alert(1)"], ~r/:href must be a path/},
          {[shortcut: "mod+"], ~r/not a shortcut/},
          {[args: [x: []]], ~r/needs :run/},
          {[method: :delete], ~r/go with what the action does/},
          {[navigate: "/a", value: %{}], ~r/does not go with/},
          {[children: [Jumon.action(:x, "X"), Jumon.action(:x, "Y")]], ~r/different ids/},
          {[priority: 5000], ~r/:priority/},
          {[tone: :loud], ~r/:tone/}
        ] do
      assert_raise ArgumentError, message, fn -> Jumon.action(:a, "A", opts) end
    end

    assert_raise ArgumentError, ~r/an id cannot have a "\/"/, fn -> Jumon.action("a/b", "A") end

    assert_raise ArgumentError, ~r/name must be a non-empty string/, fn ->
      Jumon.action(:a, " ")
    end
  end

  test "arguments" do
    action =
      Jumon.action(:a, "A",
        args: [level: [options: [{"h", "High"}]], note: [optional: true]],
        run: fn _args, socket -> socket end
      )

    assert [%Jumon.Arg{type: :choice}, %Jumon.Arg{type: :text, optional: true}] = action.args
    [choice, text] = action.args
    assert Jumon.Arg.cast(choice, "h", MapSet.new()) == {:ok, "h"}
    assert Jumon.Arg.cast(choice, "x", MapSet.new()) == {:error, :invalid}
    assert Jumon.Arg.cast(text, "  ", MapSet.new()) == {:ok, nil}
    assert Jumon.Arg.cast(text, " hi ", MapSet.new()) == {:ok, "hi"}

    search = Jumon.Arg.new(:person, search: fn _q -> [] end)
    assert Jumon.Arg.cast(search, "ada", MapSet.new(["ada"])) == {:ok, "ada"}
    assert Jumon.Arg.cast(search, "eve", MapSet.new(["ada"])) == {:error, :invalid}
  end

  test "shortcuts are normalized" do
    assert Jumon.Shortcut.normalize("Cmd+Option+K") == {:ok, "alt+meta+k"}
    assert Jumon.Shortcut.normalize("shift++") == {:ok, "shift++"}
    assert Jumon.Shortcut.normalize("esc") == {:ok, "escape"}
    assert Jumon.Shortcut.normalize("hyper+k") == :error
    assert Jumon.Shortcut.normalize("a b c d e") == :error
  end
end
