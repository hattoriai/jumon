# Actions

An action is what a person finds in the palette and runs. Make one with
`Jumon.action/3` (imported by `use Jumon.Commands`): an id, unique in the
palette, a name, and options.

```elixir
action(:new_project, "New project", event: "new_project", shortcut: "c", icon: "hero-plus")
```

`Jumon.Action` lists every option. This guide shows how they go together.

## What an action does

An action does one thing, or none (a group of children):

| Option | Runs | Like |
| --- | --- | --- |
| `navigate: path` | in the browser: a live navigation | `<.link navigate>` |
| `patch: path` | in the browser: a patch of this LiveView | `<.link patch>` |
| `href: url` | in the browser: the page loads | `<.link href>` |
| `href: url, method: :delete` | in the browser: a form with the CSRF token | `<.link method>` |
| `href: url, target: "_blank"` | in the browser: a new tab | |
| `event: name, value: map` | the LiveView's `handle_event/3` | `phx-click` |
| `js: %JS{}` | the JS commands, in the browser | `phx-click={JS...}` |
| `copy: text` | the clipboard | |
| `run: fun` | the function, in the LiveView | |

`navigate` and `patch` take only paths of the app (`/projects`); `href`
takes a path, or an `http`, `https`, `mailto` or `tel` URL.

A navigation to a path of another `live_session` loads the page, as
`<.link navigate>` does.

## Runs on the server

```elixir
action(:archive, "Archive this project", run: &archive/1)

defp archive(socket) do
  MyApp.Projects.archive!(socket.assigns.project)
  push_navigate(socket, to: ~p"/projects")
end
```

The function gets the socket of the LiveView where the palette is (and the
values of its arguments first, for an action with `:args`). It returns:

* the socket, or `{:noreply, socket}`: done, and the palette closes;
* `{:error, message, socket}` (or `{:error, message}`): the palette shows
  the message and stays open.

A function that raises crashes the LiveView, as a `handle_event/3` that
raises does.

The browser never has the function, only the action's id. When the person
runs it, the hook finds the action again among those it gave this
LiveView (or the results its searches gave it), and checks it:

* `disabled: true` (or a reason) refuses it;
* `allow: fn socket -> boolean end` runs again, on the socket as it is
  now, and refuses it unless it returns `true`.

Leave out of `actions/1` what a person may not see; give `:allow` to what
may change while the page is open (a role, the state of a record).

## Sections, order and the look of an action

```elixir
action(:billing, "Billing",
  section: "Settings",
  subtitle: "Plans and invoices",
  keywords: ~w(invoice payment plan),
  icon: "hero-credit-card",
  badge: "New",
  priority: 10,
  navigate: ~p"/settings/billing"
)
```

* `:section` is the heading of the group; actions without one go under
  "Actions". Sections keep the order in which their actions come, and
  with a query, the best match leads.
* `:keywords` find the action without showing ("logout" finds "Sign
  out").
* `:priority` moves an action up in its group and in the results.
* `:icon` is the name of an icon of your app, see the
  [Theming](theming.md) guide; `"🚀"` (an emoji) works too, as do
  `:glyph` and `:avatar`.
* `tone: :danger` marks an action that destroys something;
  `confirm: "question"` asks before it runs.
* `disabled: "Only the owner sees billing"` shows the action, and says
  why it does not run.
* `hidden: true` leaves it out of the list: it runs by its shortcut, or
  from its parent's page.
* `keep_open: true` keeps the palette open after it runs.

## Children

An action with `:children` opens a page of them. Its name is the
breadcrumb, and Backspace (in an empty box) or Escape goes back:

```elixir
action(:theme, "Theme",
  icon: "hero-swatch",
  children: [
    action(:light, "Light", js: JS.dispatch("app:theme", detail: %{theme: "light"})),
    action(:dark, "Dark", js: JS.dispatch("app:theme", detail: %{theme: "dark"})),
    action(:system, "System", js: JS.dispatch("app:theme", detail: %{theme: "system"}))
  ]
)
```

A search from the first page finds children too, with their parent before
their name ("Theme › Dark").

Children are in the page's HTML, all of them. A list of hundreds is fine;
for thousands that change, use a [source](searching.md) or an
[argument](arguments.md) that searches the server.

## Actions of a page

A LiveView adds actions of its own, for what it shows. They come after the
actions of the commands module, and leave with the LiveView:

```elixir
def handle_params(%{"id" => id}, _uri, socket) do
  project = Projects.get!(socket.assigns.current_scope, id)

  {:noreply,
   socket
   |> assign(:project, project)
   |> Jumon.Live.put_actions([
     action(:rename, "Rename this project…",
       section: project.name,
       args: [name: [type: :text, placeholder: project.name]],
       run: &rename/2
     ),
     action(:copy_id, "Copy the project's id", copy: project.id)
   ])}
end
```

`Jumon.Live.put_actions/3` takes a group name (`:page` by default), which
replaces the group's earlier actions; `Jumon.Live.delete_actions/2`
removes a group. `Jumon.Live.refresh/1` asks the commands module again,
when what it reads changes (the person changed role).

## More actions on an action

`:actions` gives an action more actions, in the menu of a result (→ on
it, or its "…" button). The first is also ⌘Enter:

```elixir
action(project.id, project.name,
  navigate: ~p"/projects/#{project}",
  actions: [
    action(:settings, "Open its settings", navigate: ~p"/projects/#{project}/settings"),
    action(:archive, "Archive", run: fn socket -> archive(socket, project) end, tone: :danger)
  ]
)
```

An action that navigates or opens a link also has "Open in a new tab" and
"Copy link" there (`link_actions={false}` on the palette leaves them out).

## Events of the palette

The palette element dispatches DOM events, for analytics or anything of
your own: `jumon:opened`, `jumon:closed`, and `jumon:run` with the
action's id in `detail`. It listens to `jumon:open`, `jumon:close` and
`jumon:toggle`, which `command_button/1` and
`JS.dispatch("jumon:open", to: "#jumon")` send.

From the server, `Jumon.Live.open/2` opens it (at a query, or on the page
of an action) and `Jumon.Live.close/2` closes it.
