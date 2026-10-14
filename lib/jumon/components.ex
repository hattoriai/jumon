defmodule Jumon.Components do
  @moduledoc """
  Function components for the palette.

      import Jumon.Components

      <.command_palette jumon={@jumon}>
        <:icon :let={name}><.icon name={name} class="size-4" /></:icon>
      </.command_palette>

      <.command_button for="jumon" />

  `command_palette/1` goes once in the app's layout, where every LiveView
  of the `live_session` renders it; `@jumon` is the assign of the
  `Jumon.Live` hook. It needs the `Jumon` hook in the LiveSocket and the
  Jumon CSS (see the README). The palette is closed until the person
  presses its shortcut (⌘K, or Ctrl+K), or clicks a `command_button/1`.

  ## Icons

  Jumon has no icons of its own for actions: an action's `:icon` is the
  name of an icon of your app. With the `:icon` slot, the palette shows the
  slot for each name, rendered by your own component (Phoenix's `<.icon>`,
  Lucide, Font Awesome, an SVG of your own); the browser copies it into
  each row. Without the slot, it shows `<span class={name}>`, which is
  already an icon in a Phoenix app: `icon: "hero-home"`.

  The slot is rendered for the icons of the actions, and of the names in
  `icons`: give there the icons of the results of your sources, which the
  page does not have before a search.
  """

  use Phoenix.Component

  alias Jumon.{Action, Messages, Shortcut}

  @v 1

  @doc """
  Renders the command palette.

  Give it `jumon={@jumon}` in a LiveView with the `Jumon.Live` hook. On a
  page without LiveView, give it `commands` and `conn` instead: it shows
  the actions of the commands module for the conn that navigate, open a
  link, run JS commands or copy a text (those that need a LiveView are
  left out), with no sources (see the [Pages](pages.md) guide).
  """
  attr :jumon, :map, default: nil, doc: "the `@jumon` assign of the `Jumon.Live` hook"
  attr :commands, :atom, default: nil, doc: "a commands module, on a page without LiveView"
  attr :conn, :any, default: nil, doc: "the conn, on a page without LiveView"
  attr :id, :string, default: "jumon", doc: "the id of the palette"

  attr :shortcut, :any,
    default: "mod+k",
    doc: "the shortcut that opens the palette, or a list of them; `nil` for none"

  attr :placeholder, :string, default: nil, doc: "the words in the empty box"

  attr :locale, :string,
    default: nil,
    doc:
      "the locale of the palette's own words; the default is `config :jumon, locale:`, else \"en\""

  attr :messages, :map,
    default: nil,
    doc: "words that replace the built-in ones, see `Jumon.Messages`"

  attr :recent, :integer,
    default: 5,
    doc: "the most recent actions shown when the box is empty; 0 for none"

  attr :help, :boolean,
    default: true,
    doc: "when `true`, `?` (outside a text field) and the palette list the keyboard shortcuts"

  attr :link_actions, :boolean,
    default: true,
    doc:
      "when `true`, actions that navigate or open a link have \"Open in a new tab\" and \"Copy link\""

  attr :icons, :list, default: [], doc: "more icon names to render with the `:icon` slot"
  attr :class, :any, default: nil, doc: "classes for the palette element"
  attr :rest, :global, doc: "attributes for the palette element"

  slot :icon, doc: "renders an icon by its name (`:let`), for the `:icon` of actions"

  def command_palette(assigns) do
    jumon = jumon!(assigns)
    locale = assigns.locale || Application.get_env(:jumon, :locale, "en")
    messages = Messages.for_locale(locale, assigns.messages)

    config =
      Map.merge(jumon, %{
        "locale" => locale,
        "messages" =>
          if(assigns.placeholder,
            do: Map.put(messages, "placeholder", assigns.placeholder),
            else: messages
          ),
        "options" => %{
          "shortcut" => shortcuts(assigns.shortcut),
          "recent" => assigns.recent,
          "help" => assigns.help,
          "linkActions" => assigns.link_actions,
          "icons" => assigns.icon != []
        }
      })

    assigns =
      assigns
      |> assign(:config, JSON.encode!(config))
      |> assign(:icon_names, icon_names(jumon, assigns.icons))

    ~H"""
    <div id={@id} class={["jumon", @class]} phx-hook="Jumon" data-config={@config} {@rest}>
      <div :if={@icon != []} id={@id <> "-icons"} class="jumon-icons" hidden>
        <template :for={name <- @icon_names} data-jumon-icon={name}>{render_slot(@icon, name)}</template>
      </div>
      <div id={@id <> "-ui"} class="jumon-ui" phx-update="ignore"></div>
    </div>
    """
  end

  @doc """
  Renders a button that opens the palette, with its shortcut: for a
  header, and for a touch screen, which has no keyboard shortcut.
  """
  attr :for, :string, default: "jumon", doc: "the id of the palette"

  attr :label, :string,
    default: nil,
    doc: "the words of the button; the default is \"Search or jump to…\""

  attr :shortcut, :string, default: "mod+k", doc: "the shortcut it shows; `nil` for none"

  attr :locale, :string,
    default: nil,
    doc: "the locale of its default words; the default is `config :jumon, locale:`, else \"en\""

  attr :class, :any, default: nil
  attr :rest, :global

  slot :inner_block, doc: "the content of the button, in place of the label and the shortcut"

  def command_button(assigns) do
    locale = assigns.locale || Application.get_env(:jumon, :locale, "en")
    messages = Messages.for_locale(locale)

    assigns =
      assigns
      |> assign(:text, assigns.label || messages["trigger"])
      |> assign(:aria_label, messages["openPalette"])
      |> assign(:keys, assigns.shortcut && Shortcut.normalize!(assigns.shortcut))

    ~H"""
    <button
      type="button"
      class={["jumon-button", @class]}
      aria-haspopup="dialog"
      aria-controls={@for}
      data-jumon-open={@for}
      phx-click={Phoenix.LiveView.JS.dispatch("jumon:open", to: "#" <> @for)}
      {@rest}
    >
      <%= if @inner_block != [] do %>
        {render_slot(@inner_block)}
      <% else %>
        <span class="jumon-button-label">{@text}</span>
        <span :if={@keys} class="jumon-keys" data-jumon-keys={@keys}>
          <kbd :for={key <- fallback_keys(@keys)}>{key}</kbd>
        </span>
      <% end %>
    </button>
    """
  end

  # Before the bundle shows them for the platform (⌘ K on Apple devices).
  defp fallback_keys(keys) do
    keys
    |> String.split(" ")
    |> Enum.flat_map(fn chord ->
      chord
      |> String.split("+")
      |> Enum.map(fn
        "mod" -> "Ctrl"
        "ctrl" -> "Ctrl"
        "alt" -> "Alt"
        "shift" -> "Shift"
        "meta" -> "Meta"
        key -> String.upcase(key)
      end)
    end)
  end

  defp jumon!(%{jumon: %{"v" => _} = jumon}), do: Map.put(jumon, "live", true)

  defp jumon!(%{commands: module, conn: conn}) when is_atom(module) and module != nil do
    actions =
      conn
      |> module.actions()
      |> Enum.flat_map(&Action.flatten/1)
      |> Enum.filter(&static?/1)

    %{
      "v" => @v,
      "live" => false,
      "actions" => Enum.map(actions, &Action.to_client/1),
      "sources" => [],
      "history" =>
        case function_exported?(module, :__jumon__, 1) && module.__jumon__(:history) do
          false -> "off"
          _other -> "local"
        end
    }
  end

  defp jumon!(_assigns) do
    raise ArgumentError,
          "Jumon.Components.command_palette/1 needs jumon={@jumon} (the assign of the Jumon.Live hook), " <>
            "or commands and conn on a page without LiveView"
  end

  # What a page without LiveView can do: no :run, no :event, no :args.
  defp static?(%Action{perform: {kind, _, _}}) when kind in [:navigate, :patch, :href], do: true
  defp static?(%Action{perform: {kind, _}}) when kind in [:js, :copy], do: true
  defp static?(%Action{perform: nil, children: [_ | _]}), do: true
  defp static?(_action), do: false

  defp shortcuts(nil), do: []
  defp shortcuts(shortcut) when is_binary(shortcut), do: [Shortcut.normalize!(shortcut)]
  defp shortcuts(list) when is_list(list), do: Enum.map(list, &Shortcut.normalize!/1)

  defp icon_names(jumon, extra) do
    from_actions =
      Enum.flat_map(jumon["actions"], fn action ->
        [action["icon"]] ++
          Enum.map(action["actions"] || [], & &1["icon"]) ++
          Enum.flat_map(action["args"] || [], fn arg ->
            Enum.map(arg["options"] || [], & &1["icon"])
          end)
      end)

    (from_actions ++ Enum.map(extra, &to_string/1))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end
end
