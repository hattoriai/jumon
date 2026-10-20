# Jumon

![Jumon — Commands for Phoenix](https://raw.githubusercontent.com/hattoriai/jumon/main/media/banner.png)

Jumon (呪文, "spell") is a command palette for Phoenix. It gives your app:

* a palette for every LiveView of a `live_session`, opened with ⌘K (or
  Ctrl+K) or a button: actions that navigate, push events, run JS commands,
  open links, copy, or run a function on the server;
* `Jumon.Commands`, one module with the actions of your app, the sources
  it searches, and where it keeps the history of each person, read for
  each socket, so that each person sees what they may do;
* actions of a LiveView's own page, which leave with it, and actions of a
  search's results, with more actions on each (→);
* pages: actions with children, and actions that ask for their arguments
  (a choice, a search of the server, a text) before they run;
* search as you type: the actions in the browser at once, with a fuzzy
  match that forgives a typo and ignores accents, and the sources of the
  server as they answer, the slow ones in a task;
* keyboard shortcuts for any action, sequences such as `g i`, and `?` for
  a page of them all;
* a history of what each person runs, for "Recent" and for the order of
  the results: in the browser, or on the server with Ecto (PostgreSQL or
  SQLite);
* `Jumon.Test`, to search and run actions in `Phoenix.LiveViewTest` with
  no browser.

The palette is a prebuilt JavaScript bundle in the Hex package. Your app
does not run Node.js for it: you add the hook and one style sheet.

![The Jumon palette in the development app: sections of actions with the app's icons, shortcuts, pages of children and arguments, and a danger tone](https://raw.githubusercontent.com/hattoriai/jumon/main/media/palette.png)

## Try it: Notebook

![Jumon in Notebook: the query "page" finds an action of the page being read, the notebook's own actions with their shortcuts, and a page from a search of the server](https://raw.githubusercontent.com/hattoriai/jumon/main/media/notebook-palette.png)

[Notebook](https://github.com/hattoriai/notebook) is a complete Phoenix
app made with Jumon, Kotoba and Koyomi. Its palette searches the pages on
the server (a typo in a title is forgiven, with `Jumon.Match`), adds the
actions of the page you read (rename it, set its due date, copy its
link), offers a day of the notebook's calendar on a page of children, and
keeps each person's history in SQLite. Clone it, run `mix setup` and
`mix phx.server`, sign in as Hattori Hanzo (its README has the details)
and press ⌘K.

## What the palette does

| | |
| --- | --- |
| Actions | navigate, patch, open a link (with a method, or in a new tab), push an event, run `Phoenix.LiveView.JS` commands, copy a text, run a function on the server; sections, keywords, subtitles, badges, priorities, a danger tone, disabled actions with a reason, a question to confirm |
| Pages | children with their breadcrumb, Backspace or Escape to go back, two thousand children drawn a screen at a time |
| Arguments | a choice of options, a search of the server, a text, asked in turn and checked again on the server before the action runs |
| Search | each word in order, at the start of words first, one typo in a long word, accents and case ignored; the same rules in Elixir (`Jumon.Match`) |
| Sources | searches of the server by name, in the reply or in a task, each under its heading with its own loading and error, the results of an older query never over a newer one |
| Results | actions of their own (→ or the "…" button), "Open in a new tab" and "Copy link" for links, ⌘Enter for the first |
| Shortcuts | chords and sequences (`mod+shift+p`, `g h`), shown for the platform (⌘ or Ctrl), not typed into text fields, the `?` page |
| History | "Recent", and frecency in the order of results: in `localStorage`, in memory (ETS), or in the database with Ecto on PostgreSQL and SQLite |
| Server | each action that runs on the server is found again by id, checked (`:allow`, `:disabled`), and run in the LiveView; telemetry for searches and runs |
| Icons | your own: an `:icon` slot that renders your icon component, Heroicons class names, emoji, avatars |
| Pages without LiveView | the actions that the browser does alone, with `mountJumon()` |
| Words | eight languages (`Jumon.Messages`), your own with Gettext |
| Theming | CSS custom properties, light and dark, the Sumi theme, forced colours, reduced motion |
| Accessibility | a modal dialog with a WAI-ARIA combobox and listbox, the active result as `aria-activedescendant`, results counted aloud, the focus given back on close, input methods (IME) left alone |

## Install

Jumon needs Elixir 1.18 or later (it uses the built-in `JSON` module),
Phoenix 1.7.14 or 1.8, and Phoenix LiveView 1.1 or later.

Add `jumon` to the deps in `mix.exs`:

```elixir
def deps do
  [
    {:jumon, "~> 0.2"}
  ]
end
```

Then run:

```sh
mix deps.get
mix jumon.install
```

The installer adds the hook to `assets/js/app.js` and the style sheet to
`assets/css/app.css`, writes `lib/my_app_web/commands.ex` when it is
missing, and prints what it changed and what is left. Give `--dry-run` to
see the changes first. It does not add what a file already has, so you can
run it again.

### The manual steps

To make the same changes by hand, import the hook in `assets/js/app.js`
and add it to the hooks of the `LiveSocket`:

```js
import { Jumon } from "jumon"

const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, Jumon},
})
```

Import the style sheet in `assets/css/app.css` (and the Sumi theme, if you
want it: Sumi is the design system of Hattori AI, the makers of Jumon,
Koyomi and Kotoba). Put these lines below the other `@import` lines of
`app.css`:

```css
@import "../../deps/jumon/priv/static/jumon.css";
/* @import "../../deps/jumon/priv/static/jumon-sumi.css"; */
```

### `NODE_PATH=deps`

`import { Jumon } from "jumon"` resolves through the `NODE_PATH` of your
esbuild profile, which must have `deps/`. The Phoenix generators already
set it. If your profile has no `NODE_PATH`, add it in `config/config.exs`:

```elixir
env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
```

## Use

The commands of your app:

```elixir
defmodule MyAppWeb.Commands do
  use Jumon.Commands
  use MyAppWeb, :verified_routes

  @impl true
  def actions(socket) do
    [
      action(:home, "Home", navigate: ~p"/", section: "Go to", shortcut: "g h", icon: "hero-home"),
      action(:new_project, "New project", event: "new_project", shortcut: "c", icon: "hero-plus"),
      action(:invite, "Invite someone…",
        args: [email: [type: :text, placeholder: "Their email"]],
        run: &invite/2,
        allow: &admin?/1
      ),
      action(:sign_out, "Sign out", href: ~p"/users/log-out", method: :delete, icon: "hero-arrow-right-on-rectangle")
    ]
  end

  @impl true
  def sources(socket) do
    scope = socket.assigns.current_scope
    [projects: [search: &MyApp.Projects.search(scope, &1), label: "Projects"]]
  end

  defp invite(%{email: email}, socket) do
    MyApp.Accounts.invite(socket.assigns.current_scope, email)
    Phoenix.LiveView.put_flash(socket, :info, "Invited #{email}")
  end

  defp admin?(socket), do: socket.assigns.current_scope.user.admin?
end
```

Mount them in the router, after the hooks that assign what they read:

```elixir
live_session :default,
  on_mount: [{MyAppWeb.UserAuth, :mount_current_scope}, {Jumon.Live, MyAppWeb.Commands}] do
  live "/", HomeLive
end
```

Render the palette once, in your layout, with your own icons:

```heex
<Jumon.Components.command_palette jumon={@jumon}>
  <:icon :let={name}><.icon name={name} class="size-4" /></:icon>
</Jumon.Components.command_palette>
```

`@jumon` is an assign of every LiveView of the `live_session`; pass it on
to your layout (`<Layouts.app flash={@flash} jumon={@jumon}>`). The
palette's own events are handled by the hook: a LiveView needs no
`handle_event` clause for them.

## Guides

* [Quickstart](guides/quickstart.md): install, the commands, the layout.
* [Actions](guides/actions.md): what an action does, sections, children,
  the actions of a page and of a result.
* [Searching](guides/searching.md): how the palette matches, and the sources of
  the server.
* [Arguments](guides/arguments.md): actions that ask before they run.
* [Shortcuts](guides/shortcuts.md): chords, sequences, the keys of the
  palette.
* [History](guides/history.md): "Recent" and frecency, in the browser or
  in your database.
* [Pages without LiveView](guides/pages.md): the palette of a controller's
  page.
* [Testing](guides/testing.md): `Jumon.Test` with `Phoenix.LiveViewTest`.
* [Theming](guides/theming.md): the `--jumon-*` properties, dark mode, the
  Sumi theme and your icons.
* [Accessibility](guides/accessibility.md): the roles and the keyboard.
* [Known limits](guides/limits.md).

## Development

The palette source is TypeScript in `assets/`. The built files in
`priv/static` are not in the repository; the Hex package has them.

```sh
mix deps.get
mix jumon.build    # npm ci in assets/ when necessary, then esbuild
mix dev            # the development server on http://localhost:4099
```

`mix jumon.build` runs in the `:dev` environment and needs `npm`. It
empties `priv/static` and writes the four files of the package:
`jumon.esm.js`, `jumon.cjs.js`, `jumon.css` and `jumon-sumi.css`.

`mix dev` runs `dev.exs`: a small issue tracker ("Workshop") with every
kind of action, children, two thousand pages of children, arguments,
sources that answer at once and late, the history in memory, a page
without LiveView (`/plain`), and the Sumi theme at `/?theme=sumi` (and
`&dark=1`). Every page takes a `locale` query param. Set `PORT` for
another port. An esbuild watcher rebuilds the bundle, and the page
reloads.

### Tests

```sh
mix test                   # the ExUnit suite
mix test --include build   # also mix jumon.build and mix hex.build
mix test.js                # the unit tests of the TypeScript modules
mix test.e2e               # the Playwright browser tests
mix precommit              # compile, format, credo --strict and test
mix dialyzer
```

The history in the database is tested on SQLite always, and on
PostgreSQL when one is reachable (`JUMON_TEST_DATABASE_URL`, or
`postgres:postgres@localhost`); otherwise the `:postgres` tests are
excluded.

`mix test.js` runs the tests of the pure modules in `assets/test/` (the
matcher, the shortcuts and the history) with Node's test runner.
`test/fixtures/match.json` holds the matcher to the same scores in Elixir
and in TypeScript.

The browser tests in `e2e/` use Playwright, in Chromium, Firefox and
WebKit (the engine of Safari). Install the browsers once:

```sh
cd e2e && npm ci && npx playwright install chromium firefox webkit
```

`mix test.e2e` runs every spec in the three browsers, and `E2E_BROWSERS`
picks some of them. It runs `npm ci` in `e2e/` when `e2e/node_modules`
is missing, builds the bundle, and starts its own development server,
without watchers, on port 4098 (set `E2E_PORT` for another port). A
`mix dev` on port 4099 can keep running.

### Release

`mix release` (in this repository, an alias that replaces Mix's `release`
task) builds the bundle, checks that `priv/static` holds only the four
bundle files (`mix jumon.release_check`), publishes to Hex, and tags and
pushes `v<version>`.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md): when a change needs an issue
first, and what a pull request needs. Report a security problem
privately, as [SECURITY.md](SECURITY.md) says.

## License

Jumon is released under the MIT License. See `LICENSE`.

The icons of the palette's own controls are from
[Lucide](https://lucide.dev) (ISC, and MIT for those that come from
Feather). See `NOTICE`.
