# Shortcuts

## Of the actions

An action's `:shortcut` runs it while the palette is closed, and shows
beside it in the list:

```elixir
action(:new_issue, "New issue", event: "new_issue", shortcut: "c")
action(:inbox, "Inbox", navigate: ~p"/inbox", shortcut: "g i")
action(:command, "Run a command…", shortcut: ["mod+shift+p", "f1"], children: [...])
```

A shortcut is one or more chords, separated by spaces, pressed one after
the other, with at most a second between them (`"g i"`: `g`, then `i`). A
chord is its modifiers and one key, joined by `+`:

* `mod` is ⌘ on Apple devices and Ctrl elsewhere; `ctrl`, `alt` (also
  `option`), `shift` and `meta` (also `cmd`) are the keys themselves;
* the key is a letter, a digit, a punctuation character, or `enter`,
  `escape`, `backspace`, `delete`, `tab`, `space`, `up`, `down`, `left`,
  `right`, `home`, `end`, `pageup`, `pagedown`, `f1` to `f12`.

`Jumon.Shortcut` normalizes them (`"Shift+Mod+P"` is `"mod+shift+p"`) and
refuses a shortcut that is not valid when the action is made. A key that
shift types (`?`, `!`) needs no `shift+`.

The palette shows each shortcut for the platform: `⌘ ⇧ P` on a Mac,
`Ctrl Shift P` elsewhere.

### In a text field

In an input, a textarea, a select or an editable element (a Kotoba
editor), single keys and keys with shift type as usual: only chords with
⌘, Ctrl or Alt run actions there.

### What a shortcut does

A shortcut runs its action as Enter in the palette does. An action with
children, arguments or a question to confirm opens the palette on its
page or question.

## Of the palette

| Keys | |
| --- | --- |
| ⌘K, Ctrl+K | open or close the palette (the `shortcut` attribute, `nil` for none) |
| `?` | open the page of the keyboard shortcuts (`help={false}` for none) |
| ↓ ↑, Ctrl+N Ctrl+P | the next or the previous result (also Ctrl+J and Ctrl+K on a Mac) |
| Page Down, Page Up | a screen of results further |
| Home, End | the first or the last result, in an empty box |
| Enter | run the result, or open its page |
| ⌘Enter, Ctrl+Enter | the first of its actions (open a link in a new tab) |
| → | the menu of the actions of the result, at the end of the box |
| ⌘⌫, Ctrl+Backspace | remove a result of "Recent" from the history |
| Backspace | the page before, in an empty box |
| Escape | the page before, or close |

The palette's own shortcut can be another, or several:

```heex
<Jumon.Components.command_palette jumon={@jumon} shortcut={["mod+k", "/"]} />
```

A key in the middle of composing text (Japanese, Chinese, Korean input
methods) is left to the input method: Enter picks the characters, it does
not run a result.

## The page of the shortcuts

`?` (and "Keyboard shortcuts" in the palette) lists the actions that have
shortcuts, by section, and the keys of the palette. A search filters it.
