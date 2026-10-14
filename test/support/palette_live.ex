defmodule JumonTest.Auth do
  @moduledoc "Assigns the person of the test, as an app's auth hook does."
  import Phoenix.Component, only: [assign: 3]

  def on_mount(:default, _params, _session, socket) do
    {:cont, assign(socket, :user, %{id: 7, admin?: true, name: "Ada"})}
  end
end

defmodule JumonTest.Data do
  @moduledoc "The issues and people of the tests."

  def issues do
    [
      %{id: 1, title: "Fix the login form", key: "WEB-1"},
      %{id: 2, title: "Ship the palette", key: "WEB-2"},
      %{id: 3, title: "Write the guides", key: "DOC-3"}
    ]
  end

  def people do
    [{"ada", "Ada Lovelace"}, {"grace", "Grace Hopper"}, {"alan", "Alan Turing"}]
  end

  def search_issues(query) do
    for issue <- issues(),
        String.contains?(String.downcase(issue.title), String.downcase(query)) do
      Jumon.action(issue.id, issue.title,
        navigate: "/issues/#{issue.id}",
        subtitle: issue.key,
        actions: [Jumon.action(:copy_key, "Copy the key", copy: issue.key)]
      )
    end
  end

  def search_people(query) do
    Enum.filter(people(), fn {_id, name} ->
      String.contains?(String.downcase(name), String.downcase(query))
    end)
  end

  def slow_people(query) do
    Process.sleep(50)
    search_people(query)
  end
end

defmodule JumonTest.Commands do
  @moduledoc "The commands of the test app."
  use Jumon.Commands

  alias JumonTest.Data

  @impl true
  def actions(socket) do
    [
      action(:home, "Home", navigate: "/", section: "Go to", shortcut: "g h", icon: "hero-home"),
      action(:settings, "Settings",
        navigate: "/settings",
        section: "Go to",
        keywords: ~w(preferences)
      ),
      action(:new_issue, "New issue", event: "new_issue", shortcut: "c", icon: "🚀"),
      action(:theme, "Theme",
        children: [
          action(:light, "Light", js: JS.dispatch("app:theme", detail: %{theme: "light"})),
          action(:dark, "Dark", js: JS.dispatch("app:theme", detail: %{theme: "dark"}))
        ]
      ),
      action(:archive, "Archive everything",
        run: &archive/1,
        confirm: "Archive everything?",
        tone: :danger,
        allow: fn socket -> socket.assigns.user.admin? end
      ),
      action(:assign, "Assign to…",
        args: [
          person: [search: &Data.search_people/1, placeholder: "Who?"],
          note: [type: :text, optional: true, max_length: 20]
        ],
        run: &assign/2
      ),
      action(:priority, "Set priority…",
        args: [level: [options: [{"high", "High"}, {"low", "Low"}]]],
        run: fn %{level: level}, socket -> Phoenix.Component.assign(socket, :priority, level) end
      ),
      action(:fail, "Fail politely", run: fn socket -> {:error, "Not today", socket} end),
      action(:locked, "Locked", run: fn socket -> socket end, disabled: "Ask an admin"),
      action(:forbidden, "Forbidden",
        run: fn socket -> socket end,
        allow: fn _socket -> false end
      ),
      action(:greet, "Greet #{socket.assigns.user.name}", run: &greet/1)
    ]
  end

  @impl true
  def sources(_socket) do
    [
      issues: [search: &Data.search_issues/1, label: "Issues"],
      people: [search: &Data.slow_people/1, async: true, min_length: 2]
    ]
  end

  defp archive(socket), do: Phoenix.Component.assign(socket, :archived, true)

  defp assign(%{person: person, note: note}, socket) do
    {:noreply, Phoenix.Component.assign(socket, :assigned, {person, note})}
  end

  defp greet(socket), do: Phoenix.Component.assign(socket, :greeted, true)
end

defmodule JumonTest.ServerCommands do
  @moduledoc "Commands with the history in memory."
  use Jumon.Commands, history: {Jumon.History.Memory, name: JumonTest.History}

  @impl true
  def actions(_socket) do
    [
      action(:home, "Home", navigate: "/"),
      action(:ping, "Ping", run: fn socket -> Phoenix.Component.assign(socket, :pinged, true) end)
    ]
  end

  @impl true
  def history_key(socket), do: socket.assigns.user.id
end

defmodule JumonTest.PaletteLive do
  @moduledoc "A LiveView with the palette, and actions of its own page."
  use Phoenix.LiveView

  import Jumon.Components

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     Phoenix.Component.assign(socket,
       archived: false,
       assigned: nil,
       priority: nil,
       greeted: false,
       pinged: false,
       events: []
     )}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    {:noreply,
     Jumon.Live.put_actions(socket, [
       Jumon.action(:close_issue, "Close issue #{id}",
         run: fn socket -> Phoenix.Component.assign(socket, :closed, id) end
       )
     ])}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("new_issue", _params, socket) do
    {:noreply, Phoenix.Component.assign(socket, :events, ["new_issue" | socket.assigns.events])}
  end

  def handle_event("open_palette", _params, socket) do
    {:noreply, Jumon.Live.open(socket, query: "set")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <p id="state">
        archived={inspect(@archived)} assigned={inspect(@assigned)} priority={inspect(@priority)}
        greeted={inspect(@greeted)} pinged={inspect(@pinged)} closed={inspect(assigns[:closed])}
      </p>
      <.command_button />
      <.command_palette jumon={@jumon}>
        <:icon :let={name}><span class={["icon", name]}></span></:icon>
      </.command_palette>
    </main>
    """
  end
end
