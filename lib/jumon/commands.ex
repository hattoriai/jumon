defmodule Jumon.Commands do
  @moduledoc """
  The commands of an app: a module with the actions of the palette, the
  sources it searches, and where it keeps the history of each person.

      defmodule MyAppWeb.Commands do
        use Jumon.Commands, history: {Jumon.History.Ecto, repo: MyApp.Repo}

        @impl true
        def actions(socket) do
          [
            action(:home, "Home", navigate: ~p"/", section: "Go to", shortcut: "g h"),
            action(:new_issue, "New issue", event: "new_issue", shortcut: "c", icon: "plus"),
            action(:theme, "Theme", icon: "sun", children: [
              action(:light, "Light", js: JS.dispatch("app:theme", detail: %{theme: "light"})),
              action(:dark, "Dark", js: JS.dispatch("app:theme", detail: %{theme: "dark"}))
            ])
          ] ++ admin_actions(socket.assigns.current_scope)
        end

        @impl true
        def sources(socket) do
          scope = socket.assigns.current_scope
          [issues: [search: &MyApp.Issues.search(scope, &1), label: "Issues"]]
        end

        @impl true
        def history_key(socket), do: socket.assigns.current_scope.user.id
      end

  Mount it in a `live_session`, after the hooks that assign what it reads:

      live_session :default,
        on_mount: [{MyAppWeb.UserAuth, :mount_current_scope}, {Jumon.Live, MyAppWeb.Commands}] do
        ...
      end

  The callbacks get the LiveView's socket, or the `Plug.Conn` of a page
  without LiveView (see the [Pages](pages.md) guide): both have `assigns`.

  `use Jumon.Commands` imports `Jumon.action/2,3` and aliases
  `Phoenix.LiveView.JS`.

  ## Options of `use`

    * `:history` - where the palette keeps what each person runs, for
      "Recent" and for the order of the results (see the
      [History](history.md) guide): `:local` (the default: in the
      browser, with no server), `{module, opts}` for a `Jumon.History`
      on the server, or `false` for none.
  """

  alias Jumon.Action

  @typedoc "The LiveView socket, or the conn of a page without LiveView."
  @type context :: Phoenix.LiveView.Socket.t() | Plug.Conn.t()

  @doc "The actions of the palette, for this socket (or conn)."
  @callback actions(context()) :: [Action.t()]

  @doc """
  The sources that the palette searches as the person types, by name (see
  `Jumon.Source`).
  """
  @callback sources(context()) :: keyword()

  @doc """
  The key of the person in the history on the server: a user's id, for
  example. `nil` keeps no history for this socket.
  """
  @callback history_key(context()) :: term()

  @optional_callbacks sources: 1, history_key: 1

  defmacro __using__(opts) do
    quote do
      @behaviour Jumon.Commands
      import Jumon, only: [action: 2, action: 3]
      alias Phoenix.LiveView.JS

      @doc false
      def __jumon__(:history), do: unquote(Keyword.get(opts, :history, :local))
    end
  end
end
