# The Jumon development server: `mix dev`, then http://localhost:4099.
#
# One Phoenix endpoint with a small issue tracker ("Workshop") and its
# command palette: actions that navigate, push events, run JS commands,
# copy, run on the server, ask for arguments, ask to confirm; nested
# actions, two thousand pages of children, sources that answer at once
# and late; a page without LiveView; the history in memory. The browser
# tests in e2e/ run against it.
#
# The bundle rebuilds and the page reloads on a change.
#
# Query params of every page: `theme=sumi`, `dark=1`, `locale` (the words
# of the palette).
#
# Environment:
#
#   * PORT - the HTTP port (4099).
#   * JUMON_DEV_WATCH - "false" starts no esbuild watcher and no live
#     reload, for the browser tests; the bundle must be built first.

port = "PORT" |> System.get_env("4099") |> String.to_integer()
watch? = System.get_env("JUMON_DEV_WATCH") != "false"

Application.put_env(:phoenix, :json_library, JSON)
Logger.configure(level: :info)

Application.put_env(:jumon, JumonDev.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  check_origin: false,
  code_reloader: watch?,
  debug_errors: true,
  http: [ip: {127, 0, 0, 1}, port: port],
  live_view: [signing_salt: "jumon-dev-live-view-salt"],
  pubsub_server: JumonDev.PubSub,
  render_errors: [formats: [html: JumonDev.ErrorHTML], layout: false],
  secret_key_base: String.duplicate("jumon-development-secret-", 3),
  server: true,
  url: [host: "localhost"],
  watchers:
    if(watch?,
      do: [jumon_esm: {Esbuild, :install_and_run, [:jumon_esm, ~w(--watch)]}],
      else: []
    ),
  live_reload: [
    patterns: [
      ~r"priv/static/.*\.(js|css)$",
      ~r"lib/jumon/.*\.ex$"
    ]
  ]
)

defmodule JumonDev.Store do
  @moduledoc "The issues of the workshop, in an Agent."
  use Agent

  @people [
    {"ada", "Ada Lovelace", "Engineering"},
    {"grace", "Grace Hopper", "Engineering"},
    {"alan", "Alan Turing", "Research"},
    {"katherine", "Katherine Johnson", "Research"},
    {"margaret", "Margaret Hamilton", "Engineering"},
    {"hedy", "Hedy Lamarr", "Design"},
    {"radia", "Radia Perlman", "Infrastructure"},
    {"barbara", "Barbara Liskov", "Research"}
  ]

  @guides [
    {"quickstart", "Quickstart", "Install, the commands module, the layout"},
    {"actions", "Actions", "What an action does, sections, children"},
    {"search", "Search", "Sources of the server, async, the history"},
    {"arguments", "Arguments", "Choices, searches and text before an action runs"},
    {"shortcuts", "Shortcuts", "Chords, sequences, the help page"},
    {"theming", "Theming", "The --jumon-* properties, the Sumi theme, icons"}
  ]

  def start_link(_opts) do
    issues =
      [
        {"WEB-1", "The login form forgets the email", "ada", :high, :open},
        {"WEB-2", "Ship the command palette", "grace", :high, :open},
        {"WEB-3", "Dark mode for the settings page", "hedy", :medium, :open},
        {"API-4", "Rate limits for the public API", "radia", :medium, :open},
        {"API-5", "Webhooks retry forever", "margaret", :low, :closed},
        {"DOC-6", "Write the guides of the palette", "katherine", :medium, :open},
        {"DOC-7", "Screenshots for the README", "alan", :low, :closed}
      ]
      |> Enum.with_index(1)
      |> Map.new(fn {{key, title, person, priority, state}, id} ->
        {id, %{id: id, key: key, title: title, person: person, priority: priority, state: state}}
      end)

    Agent.start_link(fn -> issues end, name: __MODULE__)
  end

  def issues,
    do: Agent.get(__MODULE__, fn issues -> issues |> Map.values() |> Enum.sort_by(& &1.id) end)

  def issue(id), do: Agent.get(__MODULE__, &Map.get(&1, id))
  def people, do: @people
  def person(id), do: Enum.find(@people, &(elem(&1, 0) == id))
  def guides, do: @guides

  def update(id, fun), do: Agent.update(__MODULE__, &Map.update!(&1, id, fun))

  def create(title) do
    Agent.get_and_update(__MODULE__, fn issues ->
      id = map_size(issues) + 1

      issue = %{
        id: id,
        key: "WEB-#{id}",
        title: title,
        person: nil,
        priority: :medium,
        state: :open
      }

      {issue, Map.put(issues, id, issue)}
    end)
  end

  def archive_closed do
    Agent.update(__MODULE__, fn issues ->
      Map.new(issues, fn {id, issue} ->
        {id, if(issue.state == :closed, do: %{issue | state: :archived}, else: issue)}
      end)
    end)
  end

  def search_issues(query) do
    query = String.downcase(query)

    for issue <- issues(),
        issue.state != :archived,
        String.contains?(String.downcase(issue.title <> " " <> issue.key), query) do
      Jumon.action("#{issue.id}", issue.title,
        navigate: "/issues/#{issue.id}",
        subtitle: issue.key,
        icon: if(issue.state == :closed, do: "archive", else: "bug"),
        actions: [
          Jumon.action(:copy_key, "Copy the key", copy: issue.key, icon: "hash"),
          Jumon.action(:close, "Close the issue",
            run: fn socket -> close(socket, issue.id) end,
            icon: "archive"
          )
        ]
      )
    end
  end

  def close(socket, id) do
    update(id, &%{&1 | state: :closed})
    Phoenix.LiveView.put_flash(socket, :info, "Closed #{issue(id).key}")
  end

  def search_people(query) do
    Process.sleep(350)
    query = Jumon.Match.fold(query)

    for {id, name, team} <- @people,
        String.contains?(Jumon.Match.fold(name <> " " <> team), query) do
      %{id: id, name: name, subtitle: team, icon: "user", navigate: "/people##{id}"}
    end
  end

  def search_guides(query) do
    Process.sleep(1100)

    for {id, name, subtitle} <- @guides,
        Jumon.Match.score(Jumon.action(id, name, subtitle: subtitle), query) do
      Jumon.action(id, name,
        subtitle: subtitle,
        icon: "book-open",
        href: "https://hexdocs.pm/jumon/#{id}.html",
        target: "_blank"
      )
    end
  end
end

defmodule JumonDev.Commands do
  @moduledoc "The commands of the workshop."
  use Jumon.Commands, history: {Jumon.History.Memory, name: JumonDev.History}

  alias JumonDev.Store

  @impl true
  def actions(_context) do
    [
      action(:issues, "Issues",
        navigate: "/",
        section: "Go to",
        shortcut: "g i",
        icon: "folder-kanban"
      ),
      action(:people, "People",
        navigate: "/people",
        section: "Go to",
        shortcut: "g p",
        icon: "users"
      ),
      action(:plain, "A page without LiveView",
        href: "/plain",
        section: "Go to",
        icon: "file-text"
      ),
      action(:pages, "Go to page…",
        section: "Go to",
        icon: "hash",
        keywords: ["number"],
        children: for(n <- 1..2000, do: action("page-#{n}", "Page #{n}", patch: "/?page=#{n}"))
      ),
      action(:new_issue, "New issue",
        event: "new_issue",
        section: "Work",
        shortcut: "c",
        icon: "plus",
        keywords: ~w(create add)
      ),
      action(:assign, "Assign to…",
        section: "Work",
        icon: "user",
        shortcut: "a",
        args: [
          issue: [label: "Issue", search: &issue_values/1, placeholder: "Which issue?"],
          person: [
            label: "Person",
            search: &person_values/1,
            async: true,
            placeholder: "Assign to whom?"
          ]
        ],
        run: &assign/2
      ),
      action(:priority, "Set priority…",
        section: "Work",
        icon: "flag",
        args: [
          issue: [label: "Issue", search: &issue_values/1, placeholder: "Which issue?"],
          level: [
            label: "Priority",
            options: [{"high", "High"}, {"medium", "Medium"}, {"low", "Low"}]
          ]
        ],
        run: &priority/2
      ),
      action(:archive, "Archive the closed issues",
        section: "Work",
        icon: "archive",
        tone: :danger,
        confirm: "Archive every closed issue? They leave the list.",
        run: &archive/1
      ),
      action(:theme, "Theme",
        section: "Preferences",
        icon: "palette",
        keywords: ["appearance", "dark", "light"],
        children: [
          action(:light, "Light",
            icon: "sun",
            js: JS.dispatch("dev:theme", detail: %{theme: "light"})
          ),
          action(:dark, "Dark",
            icon: "moon",
            js: JS.dispatch("dev:theme", detail: %{theme: "dark"})
          ),
          action(:sumi, "Sumi",
            glyph: "墨",
            js: JS.dispatch("dev:theme", detail: %{theme: "sumi"})
          ),
          action(:sumi_dark, "Sumi, dark",
            glyph: "墨",
            js: JS.dispatch("dev:theme", detail: %{theme: "sumi-dark"})
          )
        ]
      ),
      action(:copy_time, "Copy the time on the server",
        section: "Preferences",
        icon: "🕰️",
        copy: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      ),
      action(:billing, "Billing",
        section: "Preferences",
        icon: "settings",
        disabled: "Only the owner sees billing"
      ),
      action(:docs, "Read the guides",
        section: "Help",
        icon: "book-open",
        href: "https://hexdocs.pm/jumon",
        target: "_blank"
      ),
      action(:sign_out, "Sign out",
        section: "Account",
        icon: "log-out",
        href: "/session",
        method: :delete,
        keywords: ~w(logout exit)
      )
    ]
  end

  @impl true
  def sources(_context) do
    [
      issues: [search: &Store.search_issues/1, label: "Issues"],
      people: [search: &Store.search_people/1, label: "People", async: true, min_length: 2],
      guides: [search: &Store.search_guides/1, label: "Guides", async: true, min_length: 3]
    ]
  end

  # Each browser has its history, by a visitor id in its session (the
  # browser tests run each test in a browser of its own).
  @impl true
  def history_key(context), do: context.assigns[:visitor] || "dev"

  defp issue_values(query) do
    query = String.downcase(query)

    for issue <- Store.issues(),
        issue.state == :open,
        String.contains?(String.downcase(issue.title <> issue.key), query),
        do: %{id: issue.id, name: issue.title, subtitle: issue.key, icon: "bug"}
  end

  defp person_values(query) do
    Process.sleep(200)

    for {id, name, team} <- Store.people(),
        String.contains?(Jumon.Match.fold(name), Jumon.Match.fold(query)),
        do: %{id: id, name: name, subtitle: team, icon: "user"}
  end

  defp assign(%{issue: issue, person: person}, socket) do
    id = String.to_integer(issue)
    Store.update(id, &%{&1 | person: person})
    {_id, name, _team} = Store.person(person)

    socket
    |> JumonDev.IssuesLive.reload()
    |> Phoenix.LiveView.put_flash(:info, "Assigned to #{name}")
  end

  defp priority(%{issue: issue, level: level}, socket) do
    Store.update(String.to_integer(issue), &%{&1 | priority: String.to_existing_atom(level)})
    socket |> JumonDev.IssuesLive.reload() |> Phoenix.LiveView.put_flash(:info, "Priority set")
  end

  defp archive(socket) do
    Store.archive_closed()
    socket |> JumonDev.IssuesLive.reload() |> Phoenix.LiveView.put_flash(:info, "Archived")
  end
end

defmodule JumonDev.Icons do
  @moduledoc "A few Lucide icons for the demo's :icon slot (the app's icons, not Jumon's)."
  use Phoenix.Component

  @icons %{
    "house" =>
      ~s(<path d="M15 21v-8a1 1 0 0 0-1-1h-4a1 1 0 0 0-1 1v8"/><path d="M3 10a2 2 0 0 1 .709-1.528l7-6a2 2 0 0 1 2.582 0l7 6A2 2 0 0 1 21 10v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>),
    "plus" => ~s(<path d="M5 12h14"/><path d="M12 5v14"/>),
    "user" =>
      ~s(<path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>),
    "users" =>
      ~s(<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><path d="M16 3.128a4 4 0 0 1 0 7.744"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><circle cx="9" cy="7" r="4"/>),
    "settings" =>
      ~s(<path d="M9.671 4.136a2.34 2.34 0 0 1 4.659 0 2.34 2.34 0 0 0 3.319 1.915 2.34 2.34 0 0 1 2.33 4.033 2.34 2.34 0 0 0 0 3.831 2.34 2.34 0 0 1-2.33 4.033 2.34 2.34 0 0 0-3.319 1.915 2.34 2.34 0 0 1-4.659 0 2.34 2.34 0 0 0-3.32-1.915 2.34 2.34 0 0 1-2.33-4.033 2.34 2.34 0 0 0 0-3.831A2.34 2.34 0 0 1 6.35 6.051a2.34 2.34 0 0 0 3.319-1.915"/><circle cx="12" cy="12" r="3"/>),
    "moon" =>
      ~s(<path d="M20.985 12.486a9 9 0 1 1-9.473-9.472c.405-.022.617.46.402.803a6 6 0 0 0 8.268 8.268c.344-.215.825-.004.803.401"/>),
    "sun" =>
      ~s(<circle cx="12" cy="12" r="4"/><path d="M12 2v2"/><path d="M12 20v2"/><path d="m4.93 4.93 1.41 1.41"/><path d="m17.66 17.66 1.41 1.41"/><path d="M2 12h2"/><path d="M20 12h2"/><path d="m6.34 17.66-1.41 1.41"/><path d="m19.07 4.93-1.41 1.41"/>),
    "log-out" =>
      ~s(<path d="m16 17 5-5-5-5"/><path d="M21 12H9"/><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/>),
    "file-text" =>
      ~s(<path d="M6 22a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h8a2.4 2.4 0 0 1 1.704.706l3.588 3.588A2.4 2.4 0 0 1 20 8v12a2 2 0 0 1-2 2z"/><path d="M14 2v5a1 1 0 0 0 1 1h5"/><path d="M10 9H8"/><path d="M16 13H8"/><path d="M16 17H8"/>),
    "folder-kanban" =>
      ~s(<path d="M4 20h16a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.93a2 2 0 0 1-1.66-.9l-.82-1.2A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13c0 1.1.9 2 2 2Z"/><path d="M8 10v4"/><path d="M12 10v2"/><path d="M16 10v6"/>),
    "bug" =>
      ~s(<path d="M12 20v-9"/><path d="M14 7a4 4 0 0 1 4 4v3a6 6 0 0 1-12 0v-3a4 4 0 0 1 4-4z"/><path d="M14.12 3.88 16 2"/><path d="M21 21a4 4 0 0 0-3.81-4"/><path d="M21 5a4 4 0 0 1-3.55 3.97"/><path d="M22 13h-4"/><path d="M3 21a4 4 0 0 1 3.81-4"/><path d="M3 5a4 4 0 0 0 3.55 3.97"/><path d="M6 13H2"/><path d="m8 2 1.88 1.88"/><path d="M9 7.13V6a3 3 0 1 1 6 0v1.13"/>),
    "palette" =>
      ~s(<path d="M12 22a1 1 0 0 1 0-20 10 9 0 0 1 10 9 5 5 0 0 1-5 5h-2.25a1.75 1.75 0 0 0-1.4 2.8l.3.4a1.75 1.75 0 0 1-1.4 2.8z"/><circle cx="13.5" cy="6.5" r=".5" fill="currentColor"/><circle cx="17.5" cy="10.5" r=".5" fill="currentColor"/><circle cx="6.5" cy="12.5" r=".5" fill="currentColor"/><circle cx="8.5" cy="7.5" r=".5" fill="currentColor"/>),
    "flag" =>
      ~s(<path d="M4 22V4a1 1 0 0 1 .4-.8A6 6 0 0 1 8 2c3 0 5 2 7.333 2q2 0 3.067-.8A1 1 0 0 1 20 4v10a1 1 0 0 1-.4.8A6 6 0 0 1 16 16c-3 0-5-2-8-2a6 6 0 0 0-4 1.528"/>),
    "archive" =>
      ~s(<rect width="20" height="5" x="2" y="3" rx="1"/><path d="M4 8v11a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8"/><path d="M10 12h4"/>),
    "book-open" =>
      ~s(<path d="M12 5v16"/><path d="M20.001 19A2 2 0 0022 17V5a2 2 0 00-1.999-2L16 3.002A5 5 0 0012 5a5 5 0 00-4-2H4a2 2 0 00-2 2v12a2 2 0 001.999 2H8a5 5 0 014 2 5 5 0 014-2z"/>),
    "hash" =>
      ~s(<line x1="4" x2="20" y1="9" y2="9"/><line x1="4" x2="20" y1="15" y2="15"/><line x1="10" x2="8" y1="3" y2="21"/><line x1="16" x2="14" y1="3" y2="21"/>)
  }

  def names, do: Map.keys(@icons)

  attr :name, :string, required: true

  def icon(assigns) do
    assigns = assign(assigns, :shapes, Map.get(@icons, assigns.name, ""))

    ~H"""
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" width="18" height="18">{Phoenix.HTML.raw(@shapes)}</svg>
    """
  end
end

defmodule JumonDev.Layouts do
  @moduledoc """
  The root layout: the style sheets, the import map, the LiveSocket, and
  the themes (`?theme=sumi`, `&dark=1`, or the Theme actions).
  """
  use Phoenix.Component

  def root(assigns) do
    assigns =
      assigns
      |> assign(:sumi, assigns.conn.params["theme"] == "sumi")
      |> assign(:dark, assigns.conn.params["dark"] == "1")

    ~H"""
    <!DOCTYPE html>
    <html lang="en" data-theme={if(@dark, do: "dark", else: "light")} class={@sumi && "sumi"}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>Workshop · Jumon development</title>
        <link rel="stylesheet" href="/assets/jumon.css" />
        <link id="sumi" rel="stylesheet" href="/assets/jumon-sumi.css" disabled={!@sumi} />
        <style>
          :root { color-scheme: light; --page: #f7f7f8; --ink: #1f1f23; --muted: #6b6b76; --line: #e4e4e8; --card: #fff; }
          [data-theme="dark"] { color-scheme: dark; --page: #111114; --ink: #ececf1; --muted: #9a9aa6; --line: #2a2a31; --card: #18181c; }
          .sumi { --page: var(--jumon-background); --ink: var(--jumon-text); --muted: var(--jumon-muted); --line: var(--jumon-border); --card: var(--jumon-surface); }
          body { font-family: system-ui, sans-serif; margin: 0; background: var(--page); color: var(--ink); }
          .sumi body { font-family: var(--jumon-font); }
          header { display: flex; align-items: center; gap: 1rem; padding: 0.75rem 1.5rem; border-bottom: 1px solid var(--line); background: var(--card); }
          header h1 { margin: 0; font-size: 1rem; font-weight: 600; }
          header nav { display: flex; gap: 1rem; flex: 1; }
          header nav a { color: var(--muted); text-decoration: none; font-size: 0.9375rem; }
          main { max-width: 52rem; margin: 0 auto; padding: 2rem 1.5rem; }
          .issues { list-style: none; margin: 0; padding: 0; border: 1px solid var(--line); border-radius: 8px; background: var(--card); }
          .issues li { display: flex; gap: 1rem; align-items: center; padding: 0.75rem 1rem; border-top: 1px solid var(--line); }
          .issues li:first-child { border-top: 0; }
          .issues a { color: inherit; text-decoration: none; flex: 1; }
          .key, .muted { color: var(--muted); font-size: 0.875rem; }
          .tag { font-size: 0.75rem; padding: 0.125rem 0.5rem; border-radius: 999px; border: 1px solid var(--line); color: var(--muted); }
          .flash { padding: 0.5rem 0.75rem; border-radius: 6px; background: var(--card); border: 1px solid var(--line); margin-bottom: 1rem; }
          .hint { color: var(--muted); font-size: 0.875rem; margin-top: 2rem; }
          kbd { font-family: inherit; }
        </style>
        <script type="importmap">
          {
            "imports": {
              "phoenix": "/vendor/phoenix/phoenix.mjs",
              "phoenix_live_view": "/vendor/phoenix_live_view/phoenix_live_view.esm.js",
              "jumon": "/assets/jumon.esm.js"
            }
          }
        </script>
        <script type="module">
          import { Socket } from "phoenix"
          import { LiveSocket } from "phoenix_live_view"
          import { Jumon, mountJumon } from "jumon"

          window.addEventListener("dev:theme", (event) => {
            const theme = event.detail.theme
            document.documentElement.dataset.theme = theme.endsWith("dark") ? "dark" : "light"
            document.documentElement.classList.toggle("sumi", theme.startsWith("sumi"))
            document.getElementById("sumi").disabled = !theme.startsWith("sumi")
          })

          if (document.querySelector("[data-phx-main]")) {
            const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
            const liveSocket = new LiveSocket("/live", Socket, {
              hooks: { Jumon },
              params: { _csrf_token: csrfToken }
            })
            liveSocket.connect()
            window.liveSocket = liveSocket
          } else {
            mountJumon()
          }
        </script>
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end

  attr :jumon, :map, default: nil
  attr :flash, :map, default: %{}
  attr :conn, :any, default: nil
  attr :locale, :string, default: nil
  slot :inner_block

  def app(assigns) do
    ~H"""
    <header>
      <h1>Workshop</h1>
      <nav>
        <a href="/" data-phx-link="redirect" data-phx-link-state="push">Issues</a>
        <a href="/people" data-phx-link="redirect" data-phx-link-state="push">People</a>
        <a href="/plain">Without LiveView</a>
      </nav>
      <Jumon.Components.command_button locale={@locale} />
    </header>
    <main>
      <p :if={msg = Phoenix.Flash.get(@flash, :info)} class="flash" id="flash">{msg}</p>
      {render_slot(@inner_block)}
      <p class="hint">Press <span class="jumon-keys" data-jumon-keys="mod+k">Ctrl+K</span> for the palette, <kbd>?</kbd> for the shortcuts, <kbd>g</kbd> <kbd>p</kbd> for People.</p>
    </main>
    <%= if @jumon do %>
      <Jumon.Components.command_palette jumon={@jumon} locale={@locale} icons={JumonDev.Icons.names()}>
        <:icon :let={name}><JumonDev.Icons.icon name={name} /></:icon>
      </Jumon.Components.command_palette>
    <% else %>
      <Jumon.Components.command_palette commands={JumonDev.Commands} conn={@conn} locale={@locale} icons={JumonDev.Icons.names()}>
        <:icon :let={name}><JumonDev.Icons.icon name={name} /></:icon>
      </Jumon.Components.command_palette>
    <% end %>
    """
  end
end

defmodule JumonDev.IssuesLive do
  @moduledoc "The issues, and one issue, with actions of its own page."
  use Phoenix.LiveView

  alias JumonDev.Store

  @impl true
  def mount(params, _session, socket) do
    {:ok, socket |> assign(:locale, params["locale"]) |> reload()}
  end

  def reload(socket) do
    socket
    |> assign(:issues, Enum.reject(Store.issues(), &(&1.state == :archived)))
    |> assign(:issue, socket.assigns[:issue] && Store.issue(socket.assigns.issue.id))
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    issue = Store.issue(String.to_integer(id))

    {:noreply,
     socket
     |> assign(issue: issue, page: nil)
     |> Jumon.Live.put_actions([
       Jumon.action(:close_this, "Close #{issue.key}",
         section: "This issue",
         icon: "archive",
         shortcut: "mod+shift+x",
         run: fn socket -> socket |> Store.close(issue.id) |> reload() end
       ),
       Jumon.action(:copy_this, "Copy the link to #{issue.key}",
         section: "This issue",
         icon: "hash",
         copy: "http://localhost/issues/#{issue.id}"
       )
     ])}
  end

  def handle_params(params, _uri, socket) do
    {:noreply, socket |> assign(issue: nil, page: params["page"]) |> Jumon.Live.delete_actions()}
  end

  @impl true
  def handle_event("new_issue", _params, socket) do
    issue = Store.create("A new issue")
    {:noreply, socket |> reload() |> put_flash(:info, "Created #{issue.key}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <JumonDev.Layouts.app jumon={@jumon} flash={@flash} locale={@locale}>
      <%= if @issue do %>
        <p class="key">{@issue.key}</p>
        <h2 id="issue-title">{@issue.title}</h2>
        <p class="muted">State: <span id="issue-state">{@issue.state}</span> · Priority: {@issue.priority}</p>
      <% else %>
        <p :if={@page} class="muted" id="page">Page {@page}</p>
        <ul class="issues" id="issues">
          <li :for={issue <- @issues} id={"issue-#{issue.id}"}>
            <span class="key">{issue.key}</span>
            <.link navigate={"/issues/#{issue.id}"}>{issue.title}</.link>
            <span class="tag">{issue.priority}</span>
            <span class="muted">{person(issue.person)}</span>
            <span class="tag" data-state={issue.state}>{issue.state}</span>
          </li>
        </ul>
      <% end %>
    </JumonDev.Layouts.app>
    """
  end

  defp person(nil), do: "—"
  defp person(id), do: id |> Store.person() |> elem(1)
end

defmodule JumonDev.PeopleLive do
  @moduledoc "The people of the workshop."
  use Phoenix.LiveView

  @impl true
  def mount(params, _session, socket), do: {:ok, assign(socket, :locale, params["locale"])}

  @impl true
  def render(assigns) do
    ~H"""
    <JumonDev.Layouts.app jumon={@jumon} flash={@flash} locale={@locale}>
      <h2 id="people-title">People</h2>
      <ul class="issues">
        <li :for={{id, name, team} <- JumonDev.Store.people()} id={id}>{name} <span class="muted">{team}</span></li>
      </ul>
    </JumonDev.Layouts.app>
    """
  end
end

defmodule JumonDev.PlainController do
  @moduledoc "A page without LiveView: the palette mounts with mountJumon()."
  use Phoenix.Controller, formats: [:html]

  import Phoenix.Component, only: [sigil_H: 2]

  alias Phoenix.HTML.Safe

  def index(conn, params) do
    assigns = %{conn: conn, locale: params["locale"]}

    inner = ~H"""
    <JumonDev.Layouts.app conn={@conn} locale={@locale}>
      <h2 id="plain-title">Without LiveView</h2>
      <p class="muted">A controller's page: the palette has the actions that the browser does alone.</p>
    </JumonDev.Layouts.app>
    """

    page = JumonDev.Layouts.root(%{__changed__: nil, conn: conn, inner_content: inner})
    html(conn, page |> Safe.to_iodata() |> IO.iodata_to_binary())
  end

  def sign_out(conn, _params) do
    conn |> put_flash(:info, "Signed out (not really)") |> redirect(to: "/")
  end
end

defmodule JumonDev.Visitor do
  @moduledoc "Assigns the visitor id of the session, the key of its history."
  def on_mount(:default, _params, session, socket) do
    {:cont, Phoenix.Component.assign(socket, :visitor, session["visitor"])}
  end
end

defmodule JumonDev.Router do
  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:protect_from_forgery)
    plug(:put_root_layout, html: {JumonDev.Layouts, :root})
    plug(:visitor)
  end

  defp visitor(conn, _opts) do
    if get_session(conn, :visitor),
      do: conn,
      else: put_session(conn, :visitor, Base.url_encode64(:crypto.strong_rand_bytes(9)))
  end

  scope "/" do
    pipe_through(:browser)

    live_session :default, on_mount: [JumonDev.Visitor, {Jumon.Live, JumonDev.Commands}] do
      live("/", JumonDev.IssuesLive)
      live("/issues/:id", JumonDev.IssuesLive)
      live("/people", JumonDev.PeopleLive)
    end

    get("/plain", JumonDev.PlainController, :index)
    delete("/session", JumonDev.PlainController, :sign_out)
  end
end

defmodule JumonDev.ErrorHTML do
  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end

defmodule JumonDev.Endpoint do
  use Phoenix.Endpoint, otp_app: :jumon

  @session [store: :cookie, key: "_jumon_dev", signing_salt: "jumon-dev"]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session]])

  if System.get_env("JUMON_DEV_WATCH") != "false" do
    socket("/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket)
    plug(Phoenix.LiveReloader)
    plug(Phoenix.CodeReloader)
  end

  plug(Plug.Static, at: "/assets", from: Path.expand("priv/static", __DIR__))
  plug(Plug.Static, at: "/vendor/phoenix", from: {:phoenix, "priv/static"})
  plug(Plug.Static, at: "/vendor/phoenix_live_view", from: {:phoenix_live_view, "priv/static"})

  plug(Plug.Parsers, parsers: [:urlencoded, :json], pass: ["*/*"], json_decoder: JSON)
  plug(Plug.MethodOverride)
  plug(Plug.Session, @session)
  plug(JumonDev.Router)
end

# The script's process ends after this file, so the server runs in a task
# that stays alive; `mix run --no-halt` keeps the VM up.
Task.async(fn ->
  if watch?, do: {:ok, _apps} = Application.ensure_all_started(:esbuild)

  {:ok, _pid} =
    Supervisor.start_link(
      [
        {Phoenix.PubSub, name: JumonDev.PubSub},
        JumonDev.Store,
        {Jumon.History.Memory, name: JumonDev.History},
        JumonDev.Endpoint
      ],
      strategy: :one_for_one
    )

  IO.puts("Jumon development server: http://localhost:#{port}")
  Process.sleep(:infinity)
end)
