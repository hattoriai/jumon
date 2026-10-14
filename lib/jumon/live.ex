defmodule Jumon.Live do
  @moduledoc ~S"""
  The LiveView side of the palette: an `on_mount` hook that gives every
  LiveView of a `live_session` the actions of a `Jumon.Commands` module,
  answers the palette's events, and runs its actions on the server.

      live_session :default,
        on_mount: [{MyAppWeb.UserAuth, :mount_current_scope}, {Jumon.Live, MyAppWeb.Commands}] do
        live "/", HomeLive
      end

  The hook assigns `@jumon`, which the palette component renders (pass it
  on to your layout, see `Jumon.Components.command_palette/1`), and
  attaches `handle_event` and `handle_async` hooks for the palette's own
  events (`jumon:*`): a LiveView needs no clause of its own for them.

  ## Actions of a page

  A LiveView adds actions of its own, which leave with it:

      def handle_params(%{"id" => id}, _uri, socket) do
        issue = Issues.get!(id)

        {:noreply,
         socket
         |> assign(:issue, issue)
         |> Jumon.Live.put_actions([
           action(:close_issue, "Close this issue", run: &close_issue/1, icon: "check"),
           action(:copy_id, "Copy the issue's id", copy: issue.key)
         ])}
      end

  ## What runs where

  An action that navigates, patches, opens a link, pushes an event, runs
  JS commands or copies a text does so in the browser. An action with
  `:run` sends only its id (and the values of its arguments) to the
  server; the hook finds it among the actions it gave this LiveView, or
  the results its searches gave it, checks `:disabled` and `:allow`, and
  calls it there. A browser never runs a function it was not given.

  ## Telemetry

    * `[:jumon, :search, :start | :stop | :exception]` - a search of a
      source or of an argument, with `:source` (or `:action` and `:arg`)
      and `:query` in the metadata, and `:result` (a count, or `:error`)
      at the stop.
    * `[:jumon, :run, :start | :stop | :exception]` - an action that runs
      on the server, with `:id` in the metadata, and `:result` (`:ok` or
      `:error`) at the stop.
  """

  require Logger

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, push_event: 3, put_private: 3]

  alias Jumon.{Action, Arg, Source}
  alias Phoenix.LiveView.Socket

  @v 1
  @max_offered 1000
  @max_query 200

  defmodule State do
    @moduledoc false
    defstruct [
      :module,
      :history,
      :history_key,
      base: [],
      groups: [],
      registry: %{},
      sources: [],
      offered: %{},
      offered_order: [],
      arg_offered: %{},
      pending: []
    ]
  end

  @doc """
  The `on_mount` hook: `{Jumon.Live, MyAppWeb.Commands}`. See the module
  docs.
  """
  @spec on_mount(module(), map() | :not_mounted_at_router, map(), Socket.t()) ::
          {:cont, Socket.t()}
  def on_mount(module, _params, _session, %Socket{} = socket) when is_atom(module) do
    {:cont, mount(socket, module)}
  end

  @doc """
  Mounts the palette's actions on a socket, as the `on_mount` hook does:
  for a LiveView that is not in a `live_session` with the hook.
  """
  @spec mount(Socket.t(), module()) :: Socket.t()
  def mount(%Socket{} = socket, module) when is_atom(module) do
    commands!(module)

    state = %State{module: module, history: history(module)}

    socket
    |> put_state(state)
    |> refresh()
    |> attach_hook(:jumon, :handle_event, &__MODULE__.__handle_event__/3)
    |> attach_hook(:jumon, :handle_async, &__MODULE__.__handle_async__/3)
  end

  @doc """
  Asks the commands module again for its actions, sources and history
  key: after the socket's assigns that they read have changed (the person
  signed in, or has another role).
  """
  @spec refresh(Socket.t()) :: Socket.t()
  def refresh(%Socket{} = socket) do
    state = state!(socket)
    module = state.module

    sources =
      if function_exported?(module, :sources, 1),
        do: module.sources(socket) |> Enum.map(fn {name, spec} -> Source.new(name, spec) end),
        else: []

    names = Enum.map(sources, & &1.name)

    if length(Enum.uniq(names)) != length(names),
      do: raise(ArgumentError, "Jumon: #{inspect(module)} has two sources with the same name")

    state = %{
      state
      | base: actions!(module, module.actions(socket)),
        sources: sources,
        history_key: history_key(state.history, module, socket)
    }

    rebuild(socket, state)
  end

  @doc """
  Adds actions to the palette of this LiveView, in a group (`:page` by
  default) that replaces the group's earlier actions. They go after the
  actions of the commands module, and leave with the LiveView.
  """
  @spec put_actions(Socket.t(), atom() | String.t(), [Action.t()]) :: Socket.t()
  def put_actions(socket, group \\ :page, actions)

  def put_actions(%Socket{} = socket, group, actions) when is_list(actions) do
    state = state!(socket)
    actions = actions!(state.module, actions)
    groups = List.keystore(state.groups, group, 0, {group, actions})
    rebuild(socket, %{state | groups: groups})
  end

  @doc "Removes a group of actions that `put_actions/3` added."
  @spec delete_actions(Socket.t(), atom() | String.t()) :: Socket.t()
  def delete_actions(%Socket{} = socket, group \\ :page) do
    state = state!(socket)
    rebuild(socket, %{state | groups: List.keydelete(state.groups, group, 0)})
  end

  @doc """
  The actions of the palette of this socket, each followed by its
  children: the commands module's, then the groups of `put_actions/3`.
  """
  @spec actions(Socket.t()) :: [Action.t()]
  def actions(%Socket{} = socket) do
    state = state!(socket)
    state |> all_actions() |> Enum.flat_map(&Action.flatten/1)
  end

  @doc """
  Opens the palette. Options: `:query` (the text in its box), `:page` (the
  id of an action with children or arguments, whose page it opens) and
  `:id` (the palette's id, for a page with more than one).
  """
  @spec open(Socket.t(), keyword()) :: Socket.t()
  def open(%Socket{} = socket, opts \\ []) do
    push_event(socket, "jumon:open", %{
      "v" => @v,
      "id" => opts[:id],
      "query" => opts[:query],
      "page" => opts[:page] && to_string(opts[:page])
    })
  end

  @doc "Closes the palette."
  @spec close(Socket.t(), keyword()) :: Socket.t()
  def close(%Socket{} = socket, opts \\ []) do
    push_event(socket, "jumon:close", %{"v" => @v, "id" => opts[:id]})
  end

  ## The state

  defp state!(%Socket{private: %{jumon: %State{} = state}}), do: state

  defp state!(_socket) do
    raise ArgumentError,
          "Jumon: this LiveView has no palette; add {Jumon.Live, MyAppWeb.Commands} to the on_mount of its live_session"
  end

  defp put_state(socket, state), do: put_private(socket, :jumon, state)

  defp commands!(module) do
    unless Code.ensure_loaded?(module) and function_exported?(module, :actions, 1) do
      raise ArgumentError,
            "Jumon: #{inspect(module)} is not a commands module; it needs `use Jumon.Commands` and actions/1"
    end
  end

  defp history(module) do
    history =
      if function_exported?(module, :__jumon__, 1), do: module.__jumon__(:history), else: :local

    case history do
      :local ->
        :local

      false ->
        :off

      nil ->
        :off

      {mod, opts} when is_atom(mod) and is_list(opts) ->
        {:server, mod, opts}

      mod when is_atom(mod) ->
        {:server, mod, []}

      other ->
        raise ArgumentError,
              "Jumon: :history must be :local, false or {module, opts}, not #{inspect(other)}"
    end
  end

  defp history_key({:server, _mod, _opts}, module, socket) do
    if function_exported?(module, :history_key, 1) do
      module.history_key(socket)
    else
      raise ArgumentError,
            "Jumon: #{inspect(module)} keeps the history on the server, so it needs a history_key/1 callback"
    end
  end

  defp history_key(_history, _module, _socket), do: nil

  defp actions!(module, actions) when is_list(actions) do
    Enum.each(actions, fn
      %Action{} ->
        :ok

      other ->
        raise ArgumentError,
              "Jumon: #{inspect(module)} gave #{inspect(other)}, which is not an action (use action/3)"
    end)

    actions
  end

  defp actions!(module, other) do
    raise ArgumentError, "Jumon: #{inspect(module)} gave #{inspect(other)}, not a list of actions"
  end

  defp all_actions(state), do: state.base ++ Enum.flat_map(state.groups, &elem(&1, 1))

  # The registry of the actions by id (each with its children and their
  # secondary actions), and the assign the component renders.
  defp rebuild(socket, state) do
    flat = state |> all_actions() |> Enum.flat_map(&Action.flatten/1)
    every = Enum.flat_map(flat, &[&1 | Action.secondary(&1)])

    registry =
      Enum.reduce(every, %{}, fn action, registry ->
        if Map.has_key?(registry, action.id) do
          raise ArgumentError,
                "Jumon: two actions of the palette have the id #{inspect(action.id)}"
        end

        Map.put(registry, action.id, action)
      end)

    state = %{state | registry: registry}

    socket
    |> put_state(state)
    |> assign(:jumon, client_config(state, flat))
  end

  defp client_config(state, flat) do
    %{
      "v" => @v,
      "actions" => Enum.map(flat, &Action.to_client/1),
      "sources" =>
        Enum.map(state.sources, fn source ->
          %{"name" => source.name, "label" => source.label, "minLength" => source.min_length}
        end),
      "history" =>
        case state.history do
          :local -> "local"
          :off -> "off"
          {:server, _mod, _opts} -> if state.history_key == nil, do: "off", else: "server"
        end
    }
  end

  ## Events

  @doc false
  def __handle_event__("jumon:" <> event, params, socket) when is_map(params) do
    case socket.private do
      %{jumon: %State{}} ->
        # The reply carries the ref of the event, as Jumon.Test reads it.
        {:halt, reply, socket} = event(event, params, socket)
        {:halt, Map.put_new(reply, "ref", params["ref"]), socket}

      _other ->
        {:cont, socket}
    end
  end

  def __handle_event__(_event, _params, socket), do: {:cont, socket}

  defp event("search", %{"ref" => ref, "query" => query} = params, socket)
       when is_binary(query) do
    query = String.slice(query, 0, @max_query)

    case params do
      %{"action" => action_id, "arg" => arg_name}
      when is_binary(action_id) and is_binary(arg_name) ->
        arg_search(socket, ref, query, action_id, arg_name)

      _other ->
        source_search(socket, ref, query)
    end
  end

  defp event("run", %{"id" => id} = params, socket) when is_binary(id) do
    run(socket, id, Map.get(params, "args", %{}))
  end

  defp event("used", %{"id" => id}, socket) when is_binary(id) do
    state = state!(socket)

    case lookup(state, id) do
      %Action{} = action -> record(state, action)
      nil -> :ok
    end

    {:halt, %{"v" => @v, "ok" => true}, socket}
  end

  defp event("recent", params, socket) do
    state = state!(socket)
    limit = params |> Map.get("limit", 10) |> clamp(1, 50)

    items =
      case state.history do
        {:server, mod, opts} when state.history_key != nil ->
          mod.recent(opts, state.history_key, limit)
          |> Enum.map(fn entry ->
            %{
              "id" => entry.id,
              "score" => entry.score,
              "usedAt" => DateTime.to_iso8601(entry.used_at),
              "action" => entry.action
            }
          end)

        _other ->
          []
      end

    {:halt, %{"v" => @v, "items" => items}, socket}
  end

  defp event("forget", %{"id" => id}, socket) when is_binary(id) do
    state = state!(socket)

    case state.history do
      {:server, mod, opts} when state.history_key != nil ->
        mod.forget(opts, state.history_key, id)

      _other ->
        :ok
    end

    {:halt, %{"v" => @v, "ok" => true}, socket}
  end

  defp event(_event, _params, socket), do: {:halt, %{"v" => @v, "error" => "unknown"}, socket}

  defp clamp(value, low, high) when is_integer(value), do: value |> max(low) |> min(high)
  defp clamp(_value, low, _high), do: low

  ## Searches

  defp source_search(socket, ref, query) do
    state = state!(socket)
    socket = Enum.reduce(state.pending, socket, &Phoenix.LiveView.cancel_async(&2, &1))
    length = query |> String.trim() |> String.length()
    sources = Enum.filter(state.sources, &(length >= &1.min_length))

    {results, errors, pending, socket} =
      Enum.reduce(sources, {%{}, [], [], socket}, &search_source(&1, &2, query, ref))

    state = results |> Map.values() |> List.flatten() |> offer(%{state | pending: pending})

    reply = %{
      "v" => @v,
      "ref" => ref,
      "results" => Map.new(results, fn {name, actions} -> {name, client_results(actions)} end),
      "errors" => Enum.reverse(errors),
      "pending" => pending |> Enum.reverse() |> Enum.map(&elem(&1, 2))
    }

    {:halt, reply, put_state(socket, state)}
  end

  # A source in the reply, or in a task whose result comes later.
  defp search_source(source, {results, errors, pending, socket}, query, ref) do
    prefix = source.name <> ":"
    meta = %{source: source.name}

    if source.async and Phoenix.LiveView.connected?(socket) do
      name = {:jumon, ref, source.name}
      search = source.search
      limit = source.limit
      context = if is_function(search, 2), do: socket, else: nil

      socket =
        Phoenix.LiveView.start_async(socket, name, fn ->
          Source.run(search, query, context, prefix, limit, meta)
        end)

      {results, errors, [name | pending], socket}
    else
      case Source.run(source.search, query, socket, prefix, source.limit, meta) do
        {:ok, actions} -> {Map.put(results, source.name, actions), errors, pending, socket}
        :error -> {results, [source.name | errors], pending, socket}
      end
    end
  end

  defp arg_search(socket, ref, query, action_id, arg_name) do
    state = state!(socket)

    case searchable_arg(state, query, action_id, arg_name) do
      {:ok, action, arg} -> search_arg(socket, state, {ref, query}, action, arg)
      :none -> {:halt, search_reply(ref, %{"_arg" => []}, [], []), socket}
    end
  end

  defp searchable_arg(state, query, action_id, arg_name) do
    with %Action{} = action <- lookup(state, action_id),
         %Arg{type: :search} = arg <- find_arg(action, arg_name),
         true <- String.length(String.trim(query)) >= arg.min_length do
      {:ok, action, arg}
    else
      _other -> :none
    end
  end

  defp search_arg(socket, state, {ref, query}, action, arg) do
    name = Atom.to_string(arg.name)
    meta = %{action: action.id, arg: name}

    if arg.async and Phoenix.LiveView.connected?(socket) do
      socket = Enum.reduce(state.pending, socket, &Phoenix.LiveView.cancel_async(&2, &1))
      async_name = {:jumon_arg, ref, action.id, name}
      search = arg.search
      context = if is_function(search, 2), do: socket, else: nil

      socket =
        Phoenix.LiveView.start_async(socket, async_name, fn ->
          Source.run(search, query, context, nil, 50, meta)
        end)

      state = %{state | pending: [async_name]}
      {:halt, search_reply(ref, %{}, [], ["_arg"]), put_state(socket, state)}
    else
      case Source.run(arg.search, query, socket, nil, 50, meta) do
        {:ok, items} ->
          state = offer_values(state, action.id, name, items)

          {:halt, search_reply(ref, %{"_arg" => client_results(items)}, [], []),
           put_state(socket, state)}

        :error ->
          {:halt, search_reply(ref, %{}, ["_arg"], []), socket}
      end
    end
  end

  defp search_reply(ref, results, errors, pending) do
    %{"v" => @v, "ref" => ref, "results" => results, "errors" => errors, "pending" => pending}
  end

  defp find_arg(%Action{args: args}, name),
    do: Enum.find(args, &(Atom.to_string(&1.name) == name))

  defp client_results(actions), do: Enum.map(actions, &Action.to_client/1)

  @doc false
  def __handle_async__({:jumon, ref, source}, result, socket) do
    state = state!(socket)
    state = %{state | pending: List.delete(state.pending, {:jumon, ref, source})}

    case async_result(result) do
      {:ok, actions} ->
        state = offer(actions, state)

        payload = %{
          "v" => @v,
          "ref" => ref,
          "source" => source,
          "results" => client_results(actions)
        }

        {:halt, socket |> put_state(state) |> push_event("jumon:results", payload)}

      :cancelled ->
        {:halt, put_state(socket, state)}

      :error ->
        payload = %{"v" => @v, "ref" => ref, "source" => source, "error" => true}
        {:halt, socket |> put_state(state) |> push_event("jumon:results", payload)}
    end
  end

  def __handle_async__({:jumon_arg, ref, action_id, arg_name} = name, result, socket) do
    state = state!(socket)
    state = %{state | pending: List.delete(state.pending, name)}

    case async_result(result) do
      {:ok, items} ->
        state = offer_values(state, action_id, arg_name, items)

        payload = %{
          "v" => @v,
          "ref" => ref,
          "source" => "_arg",
          "results" => client_results(items)
        }

        {:halt, socket |> put_state(state) |> push_event("jumon:results", payload)}

      :cancelled ->
        {:halt, put_state(socket, state)}

      :error ->
        payload = %{"v" => @v, "ref" => ref, "source" => "_arg", "error" => true}
        {:halt, socket |> put_state(state) |> push_event("jumon:results", payload)}
    end
  end

  def __handle_async__(_name, _result, socket), do: {:cont, socket}

  defp async_result({:ok, {:ok, actions}}), do: {:ok, actions}
  defp async_result({:ok, :error}), do: :error
  defp async_result({:exit, {:shutdown, :cancel}}), do: :cancelled

  defp async_result({:exit, reason}) do
    Logger.warning("Jumon: a search exited: #{inspect(reason)}")
    :error
  end

  # The results that a search gave this socket, which it may run: each
  # with its children and secondary actions. The oldest go first past
  # @max_offered.
  defp offer(actions, state) do
    every =
      actions
      |> Enum.flat_map(&Action.flatten/1)
      |> Enum.flat_map(&[&1 | Action.secondary(&1)])

    offered = Enum.reduce(every, state.offered, &Map.put(&2, &1.id, &1))
    order = Enum.reverse(Enum.map(every, & &1.id), state.offered_order)

    {order, dropped} =
      if length(order) > @max_offered, do: Enum.split(order, @max_offered), else: {order, []}

    keep = MapSet.new(order)

    offered =
      Enum.reduce(dropped, offered, fn id, offered ->
        if MapSet.member?(keep, id), do: offered, else: Map.delete(offered, id)
      end)

    %{state | offered: offered, offered_order: order}
  end

  defp offer_values(state, action_id, arg_name, items) do
    key = {action_id, arg_name}
    ids = MapSet.new(items, & &1.id)
    known = Map.get(state.arg_offered, key, MapSet.new())
    known = if MapSet.size(known) > @max_offered, do: ids, else: MapSet.union(known, ids)
    %{state | arg_offered: Map.put(state.arg_offered, key, known)}
  end

  defp lookup(state, id), do: Map.get(state.registry, id) || Map.get(state.offered, id)

  ## Running

  defp run(socket, id, raw_args) do
    state = state!(socket)

    with {:ok, action} <- find_runnable(state, id),
         :ok <- allowed(action, socket),
         {:ok, args} <- cast_args(state, action, raw_args, socket) do
      {reply, socket} = run_action(action, args, socket)
      if Map.has_key?(reply, "ok"), do: record(state!(socket), action)
      {:halt, Map.put(reply, "v", @v), socket}
    else
      {:error, reason} -> {:halt, %{"v" => @v, "error" => reason}, socket}
      {:error, reason, arg} -> {:halt, %{"v" => @v, "error" => reason, "arg" => arg}, socket}
    end
  end

  defp run_action(action, args, socket) do
    :telemetry.span([:jumon, :run], %{id: action.id}, fn ->
      {reply, socket} = call(action, args, socket)
      result = if Map.has_key?(reply, "error"), do: :error, else: :ok
      {{reply, socket}, %{id: action.id, result: result}}
    end)
  end

  defp find_runnable(state, id) do
    case lookup(state, id) do
      %Action{perform: {:run, _fun}, disabled: false} = action -> {:ok, action}
      %Action{perform: {:run, _fun}} -> {:error, "disabled"}
      _other -> {:error, "unknown"}
    end
  end

  defp allowed(%Action{allow: nil}, _socket), do: :ok

  defp allowed(%Action{allow: allow}, socket) do
    if allow.(socket) == true, do: :ok, else: {:error, "forbidden"}
  end

  defp cast_args(_state, %Action{args: []}, _raw, _socket), do: {:ok, %{}}

  defp cast_args(state, %Action{args: args} = action, raw, socket) when is_map(raw) do
    Enum.reduce_while(args, {:ok, %{}}, fn arg, {:ok, values} ->
      name = Atom.to_string(arg.name)
      offered = Map.get(state.arg_offered, {action.id, name}, MapSet.new())

      with {:ok, value} <- Arg.cast(arg, Map.get(raw, name), offered),
           {:ok, value} <- validate(arg, value, socket) do
        {:cont, {:ok, Map.put(values, arg.name, value)}}
      else
        {:error, :invalid} -> {:halt, {:error, "invalid", name}}
        {:error, message} when is_binary(message) -> {:halt, {:error, message, name}}
      end
    end)
  end

  defp cast_args(_state, _action, _raw, _socket), do: {:error, "invalid"}

  defp validate(%Arg{validate: nil}, value, _socket), do: {:ok, value}

  defp validate(%Arg{validate: fun}, value, socket) do
    result = if is_function(fun, 1), do: fun.(value), else: fun.(value, socket)

    case result do
      :ok -> {:ok, value}
      {:ok, value} -> {:ok, value}
      {:error, message} when is_binary(message) -> {:error, message}
      other -> raise ArgumentError, "Jumon: :validate returned #{inspect(other)}"
    end
  end

  defp call(%Action{perform: {:run, fun}} = action, args, socket) do
    result = if is_function(fun, 1), do: fun.(socket), else: fun.(args, socket)

    case result do
      %Socket{} = socket ->
        {%{"ok" => true}, socket}

      {:noreply, %Socket{} = socket} ->
        {%{"ok" => true}, socket}

      {:error, message, %Socket{} = socket} when is_binary(message) ->
        {%{"error" => "message", "message" => message}, socket}

      {:error, message} when is_binary(message) ->
        {%{"error" => "message", "message" => message}, socket}

      other ->
        raise ArgumentError,
              "Jumon: the action #{inspect(action.id)} returned #{inspect(other)}; " <>
                "return the socket, {:noreply, socket} or {:error, message, socket}"
    end
  end

  defp record(%State{history: {:server, mod, opts}, history_key: key}, action) when key != nil do
    mod.record(opts, key, action.id, Action.to_client(action))
  end

  defp record(_state, _action), do: :ok
end
