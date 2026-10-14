# Changelog

All notable changes to Jumon are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and Jumon follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.2] - 2026-10-14

### Fixed

- The palette knows when the LiveView loses its connection (the hook's
  `disconnected` and `reconnected`). A search says "Not connected" for
  each source that had no reply, and keeps the results that came before,
  where it said "Searching…" until the reload. An action that runs on the
  server or pushes an event says "Not connected", and the palette stays
  open, where it waited for a reply that never came. The `offline`
  message is used at last.
- After a reconnection, an open palette searches again: the LiveView is a
  new process, which knows none of the results of the old one, so a
  result in the list gave "That did not work".

## [0.1.1] - 2026-10-14

### Fixed

- An app's own `:focus-visible` outline no longer draws a frame around
  the search box. A global rule in an app's style sheet is as specific as
  `.jumon-input`, and comes later; the palette's rule now has two
  classes.

### Changed

- On a page of children and on the keyboard shortcuts page, the box says
  "Filter…" (the new `filter` message, in the eight languages), and no
  longer repeats the name of the page, which the breadcrumb shows.
- The README's images point at raw.githubusercontent.com, so that they
  show on hex.pm, and the README has a "Try it: Notebook" section.

## [0.1.0] - 2026-10-14

### Added

- The command palette, `Jumon.Components.command_palette/1`, and
  `Jumon.Components.command_button/1`, which opens it.
- `Jumon.Commands`: the actions of an app, the sources it searches and
  where it keeps the history, for each socket; `Jumon.Live`, the
  `on_mount` hook that gives them to the LiveViews of a `live_session`
  and answers the palette's events.
- Actions (`Jumon.action/3`) that navigate, patch, open a link (with a
  method, or in a new tab), push an event, run `Phoenix.LiveView.JS`
  commands, copy a text, or run a function on the server, found again by
  id and checked (`:allow`, `:disabled`) each time; sections, keywords,
  subtitles, badges, priorities, a danger tone, a question to confirm.
- Children on pages of their own; actions of a LiveView's page
  (`Jumon.Live.put_actions/3`); more actions on a result (→, ⌘Enter),
  with "Open in a new tab" and "Copy link" for links.
- Arguments (`Jumon.Arg`): a choice, a search of the server or a text,
  asked in turn and checked again on the server.
- Sources (`Jumon.Source`): searches of the server as the person types,
  in the reply or in a task, each under its heading.
- `Jumon.Match`: the ranking of the palette (in order, word starts, one
  typo, accents ignored), the same in Elixir and in the browser.
- Shortcuts (`Jumon.Shortcut`) for any action, sequences, the `?` page.
- The history of what each person runs (`Jumon.History`), for "Recent"
  and frecency: in the browser, in memory (`Jumon.History.Memory`), or in
  the database (`Jumon.History.Ecto`, `Jumon.Migration`,
  `mix jumon.gen.migration`) on PostgreSQL and SQLite.
- Icons of the app (the `:icon` slot, class names), emoji and avatars;
  the palette's own controls in Lucide icons.
- A list that draws only the rows in view; pages without LiveView
  (`mountJumon`); telemetry for searches and runs.
- The words of the palette in eight languages (`Jumon.Messages`).
- `Jumon.Test`, to search and run actions in `Phoenix.LiveViewTest`.
- `mix jumon.install`, the `--jumon-*` properties, a dark default and the
  Sumi theme.
