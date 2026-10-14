# Quickstart

This guide adds a command palette to a Phoenix 1.8 app, from the
dependency to the first action that runs on the server.

## Install

Add `jumon` to the deps in `mix.exs`, and run the installer:

```elixir
{:jumon, "~> 0.1"}
```

```sh
mix deps.get
mix jumon.install
```

The installer adds the `Jumon` hook to `assets/js/app.js`, the style
sheet to `assets/css/app.css`, and writes `lib/my_app_web/commands.ex`:

```elixir
defmodule MyAppWeb.Commands do
  use Jumon.Commands
  use MyAppWeb, :verified_routes

  @impl true
  def actions(_socket) do
    [
      action(:home, "Home", navigate: ~p"/", section: "Go to", shortcut: "g h", icon: "hero-home")
    ]
  end
end
```

## Mount the commands

The palette belongs to the LiveViews of a `live_session`. Add the
`Jumon.Live` hook to its `on_mount`, after the hooks that assign what the
commands read (the current scope, here):

```elixir
live_session :require_authenticated_user,
  on_mount: [{MyAppWeb.UserAuth, :require_authenticated}, {Jumon.Live, MyAppWeb.Commands}] do
  live "/projects", ProjectLive.Index
  live "/projects/:id", ProjectLive.Show
end
```

Each LiveView of the session now has an `@jumon` assign, and the hook
answers the palette's own events.

## Render the palette

Render it once, in the layout that the LiveViews use. In a Phoenix 1.8
app, that is `Layouts.app` in `lib/my_app_web/components/layouts.ex`:

```elixir
attr :jumon, :map, default: nil

def app(assigns) do
  ~H"""
  <header class="navbar">
    ...
    <Jumon.Components.command_button />
  </header>

  <main>{render_slot(@inner_block)}</main>

  <Jumon.Components.command_palette :if={@jumon} jumon={@jumon}>
    <:icon :let={name}><.icon name={name} class="size-4" /></:icon>
  </Jumon.Components.command_palette>
  """
end
```

and pass `@jumon` on from each LiveView:

```heex
<Layouts.app flash={@flash} current_scope={@current_scope} jumon={@jumon}>
```

Press ⌘K (Ctrl+K on Linux and Windows): the palette opens with "Home".

## An action on the server

An action with `:run` calls a function in the LiveView. The browser only
has its id:

```elixir
action(:archive_done, "Archive the finished projects",
  section: "Projects",
  icon: "hero-archive-box",
  tone: :danger,
  confirm: "Archive every finished project?",
  run: fn socket ->
    count = MyApp.Projects.archive_done(socket.assigns.current_scope)
    Phoenix.LiveView.put_flash(socket, :info, "Archived #{count} projects")
  end
)
```

The function returns the socket. Return `{:error, message, socket}` to
show the message in the palette and keep it open.

## A search of the server

`sources/1` gives searches that run as the person types. Their results are
actions too:

```elixir
@impl true
def sources(socket) do
  scope = socket.assigns.current_scope

  [
    projects: [
      label: "Projects",
      search: fn query ->
        for project <- MyApp.Projects.search(scope, query) do
          action(project.id, project.name, navigate: ~p"/projects/#{project}", icon: "hero-folder")
        end
      end
    ]
  ]
end
```

## Next

* [Actions](actions.md): everything an action can do.
* [Arguments](arguments.md): "Assign to…", "Rename…".
* [History](history.md): "Recent", kept in your database.
* [Testing](testing.md): the palette in `Phoenix.LiveViewTest`.
