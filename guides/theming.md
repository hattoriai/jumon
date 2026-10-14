# Theming

The palette's look is a set of CSS custom properties, `--jumon-*`, on
`:root`. The defaults are Kotoba's and Koyomi's own, so that a page with
the three looks like one thing: light, and dark under `data-theme="dark"`
(the attribute of Phoenix 1.8's themes) or the class `dark`.

The defaults have no specificity: a value set on `:root`, on an ancestor
or on `.jumon` wins.

```css
:root {
  --jumon-accent: #7c3aed;
  --jumon-radius: 16px;
  --jumon-width: 44rem;
}

[data-theme="dark"] {
  --jumon-background: #0f172a;
  --jumon-surface: #1e293b;
}
```

## The properties

| Property | |
| --- | --- |
| `--jumon-font`, `--jumon-font-mono` | the faces |
| `--jumon-font-size`, `--jumon-input-size`, `--jumon-small`, `--jumon-line-height` | the sizes of the text |
| `--jumon-text`, `--jumon-muted` | the text, and the quiet text (headings, subtitles, hints) |
| `--jumon-background`, `--jumon-surface`, `--jumon-border` | the panel, the footer and the breadcrumbs, the lines |
| `--jumon-accent`, `--jumon-accent-text` | the accent (badges, the button of a question) and the text on it |
| `--jumon-active`, `--jumon-active-text`, `--jumon-active-bar` | the active result, its text and the bar at its edge |
| `--jumon-match` | the letters that matched |
| `--jumon-danger` | an action with `tone: :danger`, and errors |
| `--jumon-key-background`, `--jumon-key-border`, `--jumon-key-text` | the keys of shortcuts |
| `--jumon-width`, `--jumon-top` | the panel's width, and its distance from the top |
| `--jumon-radius`, `--jumon-inner-radius` | the corners of the panel, and of rows and keys |
| `--jumon-shadow`, `--jumon-backdrop`, `--jumon-backdrop-filter` | the panel's shadow, and the page behind it |
| `--jumon-item-height`, `--jumon-heading-height` | the height of a row and of a heading (the list draws only the rows in view, so each kind of row has one height) |
| `--jumon-list-height` | the most height of the list |
| `--jumon-search-height`, `--jumon-space`, `--jumon-icon-size` | the box, the space, the icons |
| `--jumon-transition`, `--jumon-focus-ring` | the opening, and the focus of the button |

On a touch screen, rows are 48px high.

The classes (`.jumon-panel`, `.jumon-item`, `.jumon-active`,
`.jumon-heading`, `.jumon-footer`...) are stable, for what the properties
do not cover.

## The Sumi theme

Sumi is the design system of Hattori AI. Load `jumon-sumi.css` after
`jumon.css`:

```css
@import "../../deps/jumon/priv/static/jumon.css";
@import "../../deps/jumon/priv/static/jumon-sumi.css";
```

It maps every property to the Sumi tokens of the page (the Sumi daisyUI
themes), else to the short `--sumi-*` names, else to the Sumi palette:
paper and ink, a blade orange for the active row's edge and the letters
that matched. It follows `data-theme`, then `prefers-color-scheme`.

## Icons

Jumon has no icons for actions: an action's `:icon` names an icon of your
app.

With the `:icon` slot, the palette shows your icon component for each
name. The slot renders once for each name, in a `<template>`, and the
browser copies it into each row:

```heex
<Jumon.Components.command_palette jumon={@jumon} icons={~w(hero-folder hero-user)}>
  <:icon :let={name}><.icon name={name} class="size-4" /></:icon>
</Jumon.Components.command_palette>
```

The names are those of the actions and their options; give in `icons`
those of the results of your sources, which the page does not have before
a search. Any library works: Lucide's components, Font Awesome, your own
SVG files.

Without the slot, an icon is a `<span>` with the name as its classes,
which is already an icon in a Phoenix app (`icon: "hero-home"`, the
Heroicons of its Tailwind plugin), and with class-based libraries
(`icon: "fa-solid fa-house"`).

An emoji is an icon too (`icon: "🚀"`), as is any short text with
`glyph:`, and `avatar:` takes the URL of an image (shown round).

The few icons of the palette's own controls (the box, Enter, the chevron
of a page, back, the spinner, the menu) are from Lucide, drawn in
`currentColor` at `--jumon-icon-size`.

## Forced colours and motion

In forced colours mode (Windows High Contrast), the active row takes the
system's `Highlight`, and the matched letters are underlined. With
`prefers-reduced-motion`, the palette opens without its animation, and
the spinners stand still.
