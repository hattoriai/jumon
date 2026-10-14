# Accessibility

The palette follows the WAI-ARIA combobox pattern, in a modal dialog.

## Roles

* The palette is a native `<dialog>`, opened with `showModal()`: the rest
  of the page is inert while it is open, and it has the label "Command
  palette" (`label` in `Jumon.Messages`).
* The box is a `combobox` with `aria-expanded="true"`,
  `aria-autocomplete="list"`, and `aria-controls` naming the list.
* The list is a `listbox`; each result is an `option` with
  `aria-selected`, and `aria-disabled` when it cannot run. The list draws
  only the rows in view, so each option has `aria-setsize` and
  `aria-posinset`.
* The active result is the box's `aria-activedescendant`: the focus stays
  in the box while the arrows move through the results.
* Headings and statuses ("Searching…", "No results") are not options.
* The menu of a result's actions is a `listbox` too, which the box
  controls while it is open.
* A live region says the number of results when the person stops typing,
  "No results", errors, a question to confirm, and "Copied".

## Focus

Opening the palette moves the focus to the box; closing it gives the
focus back to what had it. Tab does nothing in the palette: it never
leaves for the page behind. The breadcrumbs' back button and the menu are
reached with the keyboard by Backspace and →, and with a pointer by a
click.

## Keyboard

Every action is reachable with the keyboard alone; see the
[Shortcuts](shortcuts.md) guide. Single-key shortcuts never fire in a text
field, and a key pressed while an input method composes text is left to
it.

## Pointer and touch

A click runs a result; the backdrop closes the palette. On a narrow
screen the palette fills the width at the top, the "…" button of the
menu is always shown, and the rows are 48px high on a touch screen.
`command_button/1` opens the palette where there is no keyboard.

## Words

The palette's own words are in eight languages, and yours with
`messages` (see `Jumon.Messages`); `lang` on the palette is its locale.
