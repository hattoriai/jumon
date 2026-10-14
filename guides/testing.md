# Testing

`Jumon.Test` tests the palette of a LiveView in `Phoenix.LiveViewTest`,
with no browser.

```elixir
import Jumon.Test

test "the palette finds and closes an issue", %{conn: conn} do
  {:ok, view, _html} = live(conn, ~p"/issues/42")

  assert "Close this issue" in names(search(view, "close"))
  assert %{"ok" => true} = run(view, :close_issue)
  assert render(view) =~ "Closed"
end
```

## Searching

`search(view, query)` returns what the palette shows for a query, in
order: the actions that match, ranked by `Jumon.Match` as the browser
ranks them, then the results of the sources, which it asks the LiveView
for as the palette does, waiting for the sources that run in a task.
Each result is a map with string keys, as the browser has it (`"id"`,
`"name"`, `"perform"`, `"source"`...). `names/1` takes their names.

```elixir
results = search(view, "acme")
assert ["Acme", "Acme Corp"] = results |> Enum.filter(&(&1["source"] == "projects")) |> names()
```

`actions(view)` returns every action of the palette, each followed by
its children.

## Running

`run(view, id, args \\ %{})` runs an action on the server, as choosing it
does, and returns the reply:

* `%{"ok" => true}`;
* `%{"error" => "unknown"}`: no such action, or one that runs in the
  browser (navigate, event, ...), whose server side is your own;
* `%{"error" => "disabled"}` or `%{"error" => "forbidden"}` (`:allow`);
* `%{"error" => "invalid", "arg" => name}`: a value that fails its
  check;
* `%{"error" => "message", "message" => text}`: what the action
  returned.

A value of a `:search` argument must be one that its search gave this
LiveView, so search first with `search_arg/5`:

```elixir
assert [%{"id" => "ada"}] = search_arg(view, :assign, :person, "ada")
assert %{"ok" => true} = run(view, :assign, %{person: "ada"})
```

The functions take the palette's id as `:id` (`"jumon"` by default).

## The rest

What the browser does (keys, the list, the pages) is for browser tests:
the palette's own e2e suite runs in Chromium, Firefox and WebKit.
`Jumon.Match` is the same ranking in Elixir, if you want to assert an
order without a LiveView.
