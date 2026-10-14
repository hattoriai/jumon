# Searching

The palette searches two things as the person types: the actions it has,
in the browser at once, and the sources of the server, as they answer.

## How the palette matches

The browser ranks the actions with these rules, the same as
`Jumon.Match` in Elixir:

* case, accents and the width of characters do not count: "cafe" finds
  "Café";
* each word of the query is found in the action, its letters in order:
  "nwiss" finds "New issue", "issue new" finds it too;
* a letter scores more at the start of the name or of a word, and right
  after the letter before it; letters far apart score less;
* a word is looked for in the name, then in the keywords, the subtitle and
  the section, each scoring less, and there only as letters next to each
  other;
* a word of four letters or more may have one typo (a letter missing,
  added, changed, or two swapped) against the start of a word: "isues"
  finds "Issues";
* the name equal to the query ranks first, then a name that starts with
  it, then a shorter name;
* `:priority` adds to the score, and so does the history: what a person
  runs often and lately comes first (see [History](history.md)).

The letters that matched are marked in the name.

With an empty box, the palette lists the actions without a parent, by
section, after "Recent".

## Sources

A source is a search of the server. The `sources/1` callback of the
commands module gives them, by name:

```elixir
@impl true
def sources(socket) do
  scope = socket.assigns.current_scope

  [
    issues: [label: "Issues", search: &MyApp.Issues.search(scope, &1)],
    people: [label: "People", search: &MyApp.Accounts.search_people(scope, &1), async: true, min_length: 2],
    docs: [label: "Docs", search: &MyApp.Docs.search/1, async: true, min_length: 3, limit: 5]
  ]
end
```

A search is a function of the query (or of the query and the socket),
which returns a list of actions, maps with `:id` and `:name`, or
`{id, name}` tuples:

```elixir
def search(scope, query) do
  for issue <- Issues.search(scope, query, limit: 20) do
    Jumon.action(issue.id, issue.title,
      subtitle: issue.key,
      navigate: "/issues/#{issue.id}",
      actions: [Jumon.action(:close, "Close", run: &close(&1, issue))]
    )
  end
end
```

The results are actions like any other: they navigate, run on the server
(the hook remembers the results it gave this socket, so it can run them),
and have actions of their own.

### When a source runs

The palette waits until the person stops typing for a moment, then sends
one search for all the sources whose `:min_length` the query reaches. A
source with `min_length: 0` also runs for the empty box, as a list of
suggestions.

* A source without `:async` runs in the LiveView process, and its results
  come in the reply.
* A source with `async: true` runs in a task of the LiveView
  (`start_async`); its results come when it ends, so a slow source never
  holds the others back. A newer query cancels the tasks of an older one.

Each source has its heading, its own "Searching…" while it runs, and its
own "Could not load" when it fails (a search that raises, or returns
anything but a list, logs a warning). The results of an older query never
replace those of a newer one, and the last results stay in the list until
the new ones come, so the list does not flicker.

The palette shows the results of a source in the order the source gives
them, under its heading, after the matching actions.

### Without a connection

While the LiveView has no connection, a source cannot answer: the
palette says "Not connected" for each source that had no reply (once,
when none did), and keeps the results that came before. An action that
runs on the server or pushes an event says "Not connected" too, and the
palette stays open. When the connection comes back, the palette searches
again.

## Telemetry

Every search of a source or of an argument is a
`[:jumon, :search, :start | :stop | :exception]` span, with `:source` (or
`:action` and `:arg`) and `:query` in its metadata, and `:result` (the
count, or `:error`) at its stop.

## Searching a list of your own

`Jumon.Match.rank/2` ranks a list of actions (or maps with `"name"`) by
the palette's rules, for a search of your own on the server:

```elixir
Jumon.Match.rank(MyApp.Commands.all(), "new pro")
```
