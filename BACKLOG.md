# Backlog

Known gaps in Jumon, each to become an issue.

## Arguments of Koyomi's kinds

An argument could be a date, a range or a time, with a Koyomi picker on
its page ("Snooze until…", "Set the due date"), and the same rules on the
server.

## Results ranked together

The results of each source are under their own heading, after the
matching actions, in the order the source gives. A score from the source
(or `Jumon.Match` on its results) could mix them with the actions by
relevance.

## Actions of a LiveComponent

`put_actions/3` takes the LiveView's socket. A LiveComponent could add
actions of its own, which leave with it.

## Remembered results across reconnections

The results that a LiveView offered are forgotten when it reconnects. A
result kept in "Recent" runs again only when the browser can do what it
does by itself.

## Words that split scripts without spaces

The matcher does not split Japanese or Chinese names into words, so a
query matches their characters in order, with no bonus at word starts.
`Intl.Segmenter` in the browser (and a segmenter in Elixir) could.

## Sections that fold

A long first page could fold its sections, and show the first few
actions of each until the person types.

## Preview of a result

Raycast shows a panel beside the list with details of the active result.
A `:preview` of an action (HTML from the server, or fields) could fill it.

## Browser tests on mobile and with screen readers

The Playwright tests run desktop Chromium, Firefox and WebKit. There are
no runs on iOS Safari, Android Chrome, or with a screen reader.
