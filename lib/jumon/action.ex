defmodule Jumon.Action do
  @moduledoc """
  An action of the palette: what a person can find and run.

  Make one with `Jumon.action/3`:

      action(:new_issue, "New issue", event: "new_issue", shortcut: "c", icon: "plus")

  The id is an atom or a string, unique in the palette; the name is what
  the palette shows and what a search matches first. See the
  [Actions](actions.md) guide.

  ## What an action does

  At most one of these options; an action with none is a group of
  `:children`, or a result that only shows something.

    * `navigate: path` - a live navigation to `path`, as `<.link
      navigate>`; to a path of another `live_session` or of a controller,
      the page loads.
    * `patch: path` - a patch of the current LiveView, as `<.link patch>`.
    * `href: url` - the page loads `url`. With `method: :delete` (or
      `:put`, `:patch`, `:post`), it is sent as a form with the CSRF token
      of the page, as `<.link method>` does. With `target: "_blank"`, it
      opens in a new tab.
    * `event: name` - pushes the event `name` to the LiveView, with
      `value:` (a map) as its params, and to `target:` (a `phx-target`)
      when given.
    * `js: %Phoenix.LiveView.JS{}` - runs the JS commands in the browser.
    * `copy: text` - copies `text` to the clipboard.
    * `run: fun` - calls `fun` on the server, in the LiveView: `fun.(socket)`,
      or `fun.(args, socket)` for an action with `:args`. It returns the
      socket, `{:noreply, socket}`, or `{:error, message, socket}` to show
      the message in the palette and keep it open. The function stays on
      the server; the browser only has the action's id.

  ## Options

    * `:subtitle` - a line under the name, or beside it.
    * `:section` - the heading of the group the action is in ("Go to",
      "Issues"). The default is the palette's general group.
    * `:keywords` - other words that find the action (`~w(logout exit)`).
    * `:icon` - the name of an icon of the app: the palette shows the
      `:icon` slot of `Jumon.Components.command_palette/1` for it (your
      `<.icon>` component, Lucide, your own SVG), or, without the slot, a
      `<span>` with the name as its classes (`"hero-home"`, the Heroicons
      of a Phoenix app; `"fa-solid fa-house"`), or an emoji (`"🚀"`).
      Jumon has no icons of its own for actions. Or `:glyph`, any
      character or short text, or `:avatar`, the URL of an image.
    * `:badge` - a short label after the name ("New", "3").
    * `:shortcut` - a shortcut, or a list of them, that runs the action
      while the palette is closed, and is shown beside it (see
      `Jumon.Shortcut`).
    * `:priority` - an integer that moves the action up (or down, below
      zero) in its group and in the results. The default is 0.
    * `:children` - actions shown when this one is chosen, on a page of
      their own, with the name as its breadcrumb.
    * `:args` - what the action asks before it runs: a keyword list of
      `Jumon.Arg` options, in order (see the [Arguments](arguments.md)
      guide).
    * `:actions` - more actions on this one, in the menu of the actions
      of a result (→ on it, or its "…" button). The first is also ⌘Enter. An action that
      navigates or opens a link has "Open in a new tab" and "Copy link"
      there already.
    * `:confirm` - a question to confirm before the action runs.
    * `:tone` - `:danger` for an action that destroys something.
    * `:disabled` - `true`, or the reason as a string: the action is shown
      but cannot run.
    * `:keep_open` - `true` to keep the palette open after the action runs.
    * `:allow` - a function of the socket that says whether the action may
      run, checked on the server again each time it runs (for `:run` and
      `:args`).
    * `:hidden` - `true` to leave the action out of the list: it runs by
      its shortcut, or from its parent's page.
  """

  alias Jumon.{Arg, Shortcut}
  alias Phoenix.LiveView.JS

  @max_id 200
  @max_text 300
  @tones [:danger]
  @methods [:get, :post, :put, :patch, :delete]
  @performs [:navigate, :patch, :href, :event, :js, :copy, :run]
  @options @performs ++
             [
               :subtitle,
               :section,
               :keywords,
               :icon,
               :glyph,
               :avatar,
               :badge,
               :shortcut,
               :priority,
               :children,
               :args,
               :actions,
               :confirm,
               :tone,
               :disabled,
               :keep_open,
               :allow,
               :hidden,
               :method,
               :target,
               :value,
               :replace
             ]

  @typedoc "What an action does."
  @type perform ::
          {:navigate, String.t(), keyword()}
          | {:patch, String.t(), keyword()}
          | {:href, String.t(), keyword()}
          | {:event, String.t(), map(), String.t() | nil}
          | {:js, JS.t()}
          | {:copy, String.t()}
          | {:run, function()}
          | nil

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          subtitle: String.t() | nil,
          section: String.t() | nil,
          keywords: [String.t()],
          icon: String.t() | nil,
          glyph: String.t() | nil,
          avatar: String.t() | nil,
          badge: String.t() | nil,
          shortcut: [String.t()],
          priority: integer(),
          perform: perform(),
          children: [t()],
          args: [Arg.t()],
          actions: [t()],
          confirm: String.t() | nil,
          tone: atom() | nil,
          disabled: boolean() | String.t(),
          keep_open: boolean(),
          allow: (Phoenix.LiveView.Socket.t() -> boolean()) | nil,
          hidden: boolean(),
          parent: String.t() | nil,
          source: String.t() | nil
        }

  @enforce_keys [:id, :name]
  defstruct [
    :id,
    :name,
    :subtitle,
    :section,
    :icon,
    :glyph,
    :avatar,
    :badge,
    :perform,
    :confirm,
    :tone,
    :allow,
    :parent,
    :source,
    keywords: [],
    shortcut: [],
    priority: 0,
    children: [],
    args: [],
    actions: [],
    disabled: false,
    keep_open: false,
    hidden: false
  ]

  @doc """
  Builds an action. See the module docs for the options.

  Raises `ArgumentError` for an option that is not one of them, a value
  that is not valid, or more than one of the options that say what the
  action does.

  ## Examples

      iex> action = Jumon.Action.new(:home, "Home", navigate: "/", shortcut: "g h")
      iex> {action.id, action.perform, action.shortcut}
      {"home", {:navigate, "/", []}, ["g h"]}

  """
  @spec new(atom() | String.t() | integer(), String.t(), keyword()) :: t()
  def new(id, name, opts \\ []) do
    unless Keyword.keyword?(opts), do: invalid!(id, "the options must be a keyword list")

    case Enum.find(Keyword.keys(opts), &(&1 not in @options)) do
      nil -> :ok
      key -> invalid!(id, "unknown option #{inspect(key)}")
    end

    id = id!(id)

    %__MODULE__{
      id: id,
      name: text!(id, :name, name),
      subtitle: opt_text!(id, opts, :subtitle),
      section: opt_text!(id, opts, :section),
      keywords: keywords!(id, Keyword.get(opts, :keywords, [])),
      icon: icon!(id, if(glyph?(opts[:icon]), do: nil, else: opts[:icon])),
      glyph: if(glyph?(opts[:icon]), do: opts[:icon], else: opt_text!(id, opts, :glyph)),
      avatar: opt_text!(id, opts, :avatar),
      badge: opt_text!(id, opts, :badge),
      shortcut: shortcuts!(Keyword.get(opts, :shortcut, [])),
      priority: priority!(id, Keyword.get(opts, :priority, 0)),
      perform: perform!(id, opts),
      children: actions!(id, :children, Keyword.get(opts, :children, [])),
      args: args!(id, Keyword.get(opts, :args, [])),
      actions: actions!(id, :actions, Keyword.get(opts, :actions, [])),
      confirm: opt_text!(id, opts, :confirm),
      tone: tone!(id, opts[:tone]),
      disabled: disabled!(id, Keyword.get(opts, :disabled, false)),
      keep_open: boolean!(id, opts, :keep_open),
      allow: allow!(id, opts[:allow]),
      hidden: boolean!(id, opts, :hidden)
    }
    |> check_args!()
  end

  defp check_args!(%{args: [_ | _], perform: perform} = action)
       when not is_tuple(perform) or elem(perform, 0) != :run do
    invalid!(action.id, "an action with :args needs :run, which gets the values")
  end

  defp check_args!(%{args: [_ | _], children: [_ | _]} = action),
    do: invalid!(action.id, "an action cannot have both :args and :children")

  defp check_args!(%{perform: perform, children: [_ | _]} = action) when perform != nil,
    do:
      invalid!(
        action.id,
        "an action with :children opens their page, it cannot also do something"
      )

  defp check_args!(action), do: action

  @doc false
  # Turns what a search or a list of options returns into an action: an
  # action, a map with :id and :name (or :label) and the options above, or
  # an `{id, name}` tuple. Returns nil for anything else.
  @spec coerce(term()) :: t() | nil
  def coerce(%__MODULE__{} = action), do: action

  def coerce({id, name})
      when (is_binary(id) or is_integer(id) or is_atom(id)) and is_binary(name),
      do: safe_new(id, name, [])

  def coerce(%{} = item) when not is_struct(item) do
    item = Map.new(item, fn {key, value} -> {to_atom(key), value} end)
    id = item[:id]
    name = item[:name] || item[:label]

    if is_nil(id) or not is_binary(name) do
      nil
    else
      opts =
        item
        |> Map.drop([:id, :name, :label])
        |> Enum.filter(fn {key, _value} -> key in @options end)

      safe_new(id, name, opts)
    end
  end

  def coerce(_other), do: nil

  defp safe_new(id, name, opts) do
    new(id, name, opts)
  rescue
    ArgumentError -> nil
  end

  defp to_atom(key) when is_atom(key), do: key

  defp to_atom(key) when is_binary(key) do
    Enum.find(@options ++ [:id, :name, :label], key, &(Atom.to_string(&1) == key))
  end

  @doc false
  # The action, its children and the children's children, each with its
  # parent's id, in order; the secondary actions are not in it.
  @spec flatten(t(), String.t() | nil) :: [t()]
  def flatten(%__MODULE__{} = action, parent \\ nil) do
    action = %{action | parent: parent}
    [action | Enum.flat_map(action.children, &flatten(&1, action.id))]
  end

  @doc false
  # The secondary actions of an action, with their ids in its namespace.
  @spec secondary(t()) :: [t()]
  def secondary(%__MODULE__{} = action) do
    Enum.map(action.actions, &%{&1 | id: action.id <> "/" <> &1.id, parent: action.id})
  end

  @doc false
  # The action as the browser reads it: everything but the functions.
  @spec to_client(t()) :: map()
  def to_client(%__MODULE__{} = action) do
    %{
      "id" => action.id,
      "name" => action.name,
      "subtitle" => action.subtitle,
      "section" => action.section,
      "keywords" => action.keywords,
      "icon" => action.icon,
      "glyph" => action.glyph,
      "avatar" => action.avatar,
      "badge" => action.badge,
      "shortcut" => action.shortcut,
      "priority" => action.priority,
      "perform" => perform_to_client(action.perform),
      "parent" => action.parent,
      "children" => action.children != [],
      "args" => Enum.map(action.args, &Arg.to_client/1),
      "actions" => action |> secondary() |> Enum.map(&to_client/1),
      "confirm" => action.confirm,
      "tone" => action.tone && Atom.to_string(action.tone),
      "disabled" => action.disabled,
      "keepOpen" => action.keep_open,
      "hidden" => action.hidden,
      "source" => action.source
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, false, [], 0] end)
    |> Map.new()
  end

  defp perform_to_client(nil), do: nil

  defp perform_to_client({:navigate, path, opts}),
    do: %{"type" => "navigate", "to" => path, "replace" => opts[:replace] == true}

  defp perform_to_client({:patch, path, opts}),
    do: %{"type" => "patch", "to" => path, "replace" => opts[:replace] == true}

  defp perform_to_client({:href, url, opts}) do
    %{
      "type" => "href",
      "to" => url,
      "method" => opts[:method] && Atom.to_string(opts[:method]),
      "target" => opts[:target]
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp perform_to_client({:event, event, value, target}) do
    %{"type" => "event", "event" => event, "value" => value, "target" => target}
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp perform_to_client({:js, js}),
    do: %{"type" => "js", "js" => js |> JS.to_encodable() |> Phoenix.json_library().encode!()}

  defp perform_to_client({:copy, text}), do: %{"type" => "copy", "text" => text}
  defp perform_to_client({:run, _fun}), do: %{"type" => "server"}

  ## Validation

  defp id!(id) when is_atom(id) and not is_nil(id) and not is_boolean(id),
    do: id!(Atom.to_string(id))

  defp id!(id) when is_integer(id), do: Integer.to_string(id)

  defp id!(id) when is_binary(id) do
    cond do
      id == "" or String.length(id) > @max_id ->
        invalid!(id, "an id must be a non-empty string of at most #{@max_id} characters")

      String.contains?(id, "/") ->
        invalid!(id, "an id cannot have a \"/\", which joins the ids of nested actions")

      String.match?(id, ~r/[\x00-\x1f\x7f]/) ->
        invalid!(id, "an id cannot have control characters")

      true ->
        id
    end
  end

  defp id!(id), do: invalid!(id, "an id must be an atom, a string or an integer")

  defp text!(id, key, value) when is_binary(value) do
    value = value |> String.replace(~r/[\x00-\x1f\x7f]+/, " ") |> String.trim()

    if value == "" or String.length(value) > @max_text,
      do: invalid!(id, "#{key} must be a non-empty string of at most #{@max_text} characters"),
      else: value
  end

  defp text!(id, key, value), do: invalid!(id, "#{key} must be a string, not #{inspect(value)}")

  defp opt_text!(id, opts, key) do
    case opts[key] do
      nil -> nil
      value -> text!(id, key, value)
    end
  end

  defp keywords!(id, keywords) when is_list(keywords),
    do: Enum.map(keywords, &text!(id, :keywords, to_string(&1)))

  defp keywords!(id, keywords) when is_binary(keywords), do: keywords!(id, [keywords])
  defp keywords!(id, _keywords), do: invalid!(id, ":keywords must be a list of strings")

  # An emoji or another short text with no ASCII letters is a glyph:
  # `icon: "🚀"` is `glyph: "🚀"`.
  defp glyph?(icon) when is_binary(icon) do
    String.length(icon) in 1..2 and not String.match?(icon, ~r/[A-Za-z0-9_-]/)
  end

  defp glyph?(_icon), do: false

  defp icon!(_id, nil), do: nil
  defp icon!(id, icon) when is_atom(icon), do: icon!(id, Atom.to_string(icon))

  # A name that is also safe as a list of CSS classes.
  defp icon!(id, icon) when is_binary(icon) do
    if String.match?(icon, ~r/\A[A-Za-z0-9_:-]+( [A-Za-z0-9_:-]+)*\z/) and byte_size(icon) <= 100,
      do: icon,
      else: invalid!(id, ":icon must be a name, or CSS classes, such as \"hero-home\"")
  end

  defp icon!(id, _icon), do: invalid!(id, ":icon must be the name of an icon")

  defp shortcuts!(shortcut) when is_binary(shortcut), do: [Shortcut.normalize!(shortcut)]
  defp shortcuts!(list) when is_list(list), do: Enum.map(list, &Shortcut.normalize!/1)

  defp priority!(_id, priority) when is_integer(priority) and priority in -1000..1000,
    do: priority

  defp priority!(id, _priority),
    do: invalid!(id, ":priority must be an integer from -1000 to 1000")

  defp perform!(id, opts) do
    case Enum.filter(@performs, &Keyword.has_key?(opts, &1)) do
      [] ->
        if Enum.any?([:method, :target, :value, :replace], &Keyword.has_key?(opts, &1)),
          do: invalid!(id, ":method, :target, :value and :replace go with what the action does")

        nil

      [perform] ->
        perform!(id, perform, opts[perform], opts)

      many ->
        invalid!(id, "give one of #{inspect(many)}, an action does one thing")
    end
  end

  defp perform!(id, kind, path, opts) when kind in [:navigate, :patch] and is_binary(path) do
    only!(id, opts, [:replace])
    {kind, path!(id, path), Keyword.take(opts, [:replace])}
  end

  defp perform!(id, :href, url, opts) when is_binary(url) do
    only!(id, opts, [:method, :target])
    method = Keyword.get(opts, :method)

    if method && method not in @methods,
      do: invalid!(id, ":method must be one of #{inspect(@methods)}")

    {:href, url!(id, url), Keyword.take(opts, [:method, :target])}
  end

  defp perform!(id, :event, event, opts) when is_binary(event) or is_atom(event) do
    only!(id, opts, [:value, :target])
    value = Keyword.get(opts, :value, %{})
    unless is_map(value), do: invalid!(id, ":value must be a map")
    target = opts[:target] && to_string(opts[:target])
    {:event, to_string(event), value, target}
  end

  defp perform!(id, :js, %JS{} = js, opts) do
    only!(id, opts, [])
    {:js, js}
  end

  defp perform!(id, :copy, text, opts) when is_binary(text) do
    only!(id, opts, [])
    {:copy, text}
  end

  defp perform!(id, :run, fun, opts) when is_function(fun, 1) or is_function(fun, 2) do
    only!(id, opts, [])
    {:run, fun}
  end

  defp perform!(id, kind, value, _opts),
    do: invalid!(id, "#{inspect(kind)} does not take #{inspect(value)}")

  defp only!(id, opts, allowed) do
    case Enum.find([:method, :target, :value, :replace] -- allowed, &Keyword.has_key?(opts, &1)) do
      nil -> :ok
      key -> invalid!(id, "#{inspect(key)} does not go with what the action does")
    end
  end

  defp path!(id, path) do
    if String.starts_with?(path, "/") and not String.starts_with?(path, "//"),
      do: path,
      else: invalid!(id, "a path to navigate or patch to must start with one \"/\"")
  end

  # A URL of the page's origin (a path) or http(s); never javascript: or data:.
  defp url!(id, url) do
    uri = URI.parse(url)

    cond do
      String.starts_with?(url, "/") -> url
      uri.scheme in ["http", "https", "mailto", "tel"] -> url
      true -> invalid!(id, ":href must be a path or an http, https, mailto or tel URL")
    end
  end

  defp actions!(id, key, list) when is_list(list) do
    actions =
      Enum.map(list, fn
        %__MODULE__{} = action -> action
        other -> invalid!(id, "#{key} must be a list of actions, not #{inspect(other)}")
      end)

    ids = Enum.map(actions, & &1.id)

    if length(Enum.uniq(ids)) != length(ids),
      do: invalid!(id, "the #{key} of an action must have different ids")

    actions
  end

  defp actions!(id, key, _list), do: invalid!(id, "#{key} must be a list of actions")

  defp args!(id, args) when is_list(args) do
    unless Keyword.keyword?(args), do: invalid!(id, ":args must be a keyword list")
    Enum.map(args, fn {name, opts} -> Arg.new(name, opts) end)
  end

  defp args!(id, _args), do: invalid!(id, ":args must be a keyword list")

  defp tone!(_id, nil), do: nil
  defp tone!(_id, tone) when tone in @tones, do: tone
  defp tone!(id, _tone), do: invalid!(id, ":tone must be one of #{inspect(@tones)}")

  defp disabled!(_id, value) when is_boolean(value), do: value
  defp disabled!(id, reason) when is_binary(reason), do: text!(id, :disabled, reason)
  defp disabled!(id, _value), do: invalid!(id, ":disabled must be a boolean or a reason")

  defp boolean!(id, opts, key) do
    case Keyword.get(opts, key, false) do
      value when is_boolean(value) -> value
      _other -> invalid!(id, "#{inspect(key)} must be a boolean")
    end
  end

  defp allow!(_id, nil), do: nil
  defp allow!(_id, fun) when is_function(fun, 1), do: fun
  defp allow!(id, _fun), do: invalid!(id, ":allow must be a function of the socket")

  defp invalid!(id, message) do
    raise ArgumentError, "Jumon: the action #{inspect(id)}: #{message}"
  end
end
