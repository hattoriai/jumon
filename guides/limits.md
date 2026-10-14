# Known limits

## Actions are in the page

The actions of the commands module and of `put_actions/3`, children
included, are in the page's HTML, as JSON, and travel again when they
change. Hundreds are fine; for thousands, or for records that change,
use a source or a `:search` argument, which the server answers.

## One palette in a LiveView

The hook keeps one set of actions for each LiveView. A LiveComponent
cannot add actions of its own; its LiveView adds them with
`put_actions/3`.

## Results run while the LiveView remembers them

The hook remembers the last thousand results that its searches gave a
LiveView, so that they can run on the server. A result older than that,
or from before a reconnection, gives "That did not work" and needs a new
search.

## The matcher reads code points

Matching folds each code point (NFKD, without marks, in lower case). It
does not split words in scripts without spaces, such as Japanese or
Chinese: a query matches their characters in order, anywhere in the name.

## The history of a result

"Recent" shows a result of a search again from what was kept when it ran.
If the record is gone (an issue deleted), the result is still there until
it is removed, and its link may answer "not found".

## Browser tests

The Playwright tests run desktop Chromium, Firefox and WebKit. There are
no runs on iOS Safari, Android Chrome, or with a screen reader.
