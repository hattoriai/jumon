# History

The palette remembers what each person runs. It shows the most recent
when the box is empty ("Recent"), and ranks what a person runs often and
lately first in the results (frecency).

## Where it is kept

The `:history` option of `use Jumon.Commands`:

| `:history` | Kept | For |
| --- | --- | --- |
| `:local` (the default) | in the browser's `localStorage` | each browser; nothing on the server |
| `{Jumon.History.Ecto, repo: MyApp.Repo}` | in your database, PostgreSQL or SQLite | each person, on any device |
| `{Jumon.History.Memory, name: MyApp.CommandHistory}` | in memory, in an ETS table | development, tests, an app on one node that can lose it on a restart |
| `{MyModule, opts}` | where your `Jumon.History` puts it | |
| `false` | nowhere | |

A history on the server needs the key of the person, from a callback of
the commands module (`nil` keeps none for that socket):

```elixir
use Jumon.Commands, history: {Jumon.History.Ecto, repo: MyApp.Repo}

@impl true
def history_key(socket), do: socket.assigns.current_scope.user.id
```

## In your database

`Jumon.History.Ecto` keeps the history in the `jumon_history` table, with
one row for a person and an action. Generate its migration, and run it:

```sh
mix jumon.gen.migration
mix ecto.migrate
```

The migration calls `Jumon.Migration`, which makes the same table on
PostgreSQL (the action in `jsonb`) and on SQLite (`ecto_sqlite3`, the
action in `TEXT`). A use is one `INSERT ... ON CONFLICT DO UPDATE`, which
both run. Give `--repo` for an app with more than one repo, and
`--prefix` (with `prefix:` in the options) for another PostgreSQL schema.

Options of `Jumon.History.Ecto`: `:repo`, `:prefix`, `:max_entries` (the
most entries of a person, 200 by default; the oldest go first) and
`:half_life` (see below).

## What is kept

The action's id, the time of its last use, its score, and the action as
the browser had it. A result of a search (an issue, a person) comes back
in "Recent" from what was kept, with no search, when the browser can do
what it does by itself (navigate, open a link, copy): it is not offered
again to run on the server.

A person removes an action from "Recent" with ⌘⌫ (Ctrl+Backspace), or
"Remove from Recent" in its menu.

## Frecency

Each use adds one to the action's score, and the score halves every 14
days (`:half_life`) after the last use: ten uses a month ago weigh less
than three this week. `Jumon.History.frecency/4` computes it; the browser
uses the same formula.

## A history of your own

A module with the `Jumon.History` behaviour (`recent/3`, `record/4`,
`forget/3`) keeps it anywhere: Redis, a document store, an API. Each
callback gets the options of `{module, opts}` and the key of the person.
