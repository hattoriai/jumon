# Pages without LiveView

A page that a controller renders has no LiveSocket, so the hook does not
run, and there is no LiveView for events, searches or actions on the
server. The palette still works there, with the actions that the browser
does alone: those that navigate, patch, open a link, run JS commands or
copy a text, and their children.

Render it with the commands module and the conn, in place of `@jumon`:

```heex
<Jumon.Components.command_palette commands={MyAppWeb.Commands} conn={@conn}>
  <:icon :let={name}><.icon name={name} class="size-4" /></:icon>
</Jumon.Components.command_palette>
```

`actions/1` gets the conn; its `assigns` are those of the controller (the
current scope of `fetch_current_scope_for_user`, for example). The actions
with `:run`, `:event` or `:args` are left out, and the sources do not run.
`navigate` and `patch` load the page.

Start the palette in the page's script, after the page loads:

```js
import { mountJumon } from "jumon"

window.addEventListener("DOMContentLoaded", () => mountJumon())
```

On a page with both (a LiveView in a controller's layout), the hook mounts
the palette of the LiveView, and `mountJumon` mounts the others.

The history of a page without LiveView is kept in the browser, even when
the commands keep it on the server.
