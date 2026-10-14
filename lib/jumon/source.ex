defmodule Jumon.Source do
  @moduledoc """
  A search of the server, run as the person types: issues, people,
  documents. The `sources/1` callback of `Jumon.Commands` gives them, by
  name:

      def sources(_socket) do
        [
          issues: [search: &MyApp.Issues.search/2, label: "Issues", min_length: 2],
          people: [search: &MyApp.People.search/1, async: true]
        ]
      end

  A source is a function of the query (or of the query and the socket),
  or a keyword list with `:search` and these options:

    * `:label` - the heading of its results; the default is its name in
      words.
    * `:min_length` - the characters of the query before it searches
      (default 1). With 0, it also searches the empty query, as a list of
      suggestions.
    * `:limit` - the most results shown (default 20, at most 100).
    * `:async` - `true` to run the search in a task of the LiveView, so
      that a slow source does not block it, and the faster sources show
      first.

  A search returns a list of actions (see `Jumon.action/3`), maps with
  `:id` and `:name` and the options of an action, or `{id, name}` tuples.
  Their ids are unique in the source (the palette gives them the source's
  name as a prefix). A result runs as any action: it navigates, runs on
  the server, has more actions. Results that are not items are dropped.

  The palette asks the sources after the person stops typing for a moment,
  and the results of an older query never replace those of a newer one.
  """

  alias Jumon.Action

  @options [:search, :label, :min_length, :limit, :async]

  @type t :: %__MODULE__{
          name: String.t(),
          label: String.t(),
          search: function(),
          min_length: non_neg_integer(),
          limit: pos_integer(),
          async: boolean()
        }

  @enforce_keys [:name, :label, :search]
  defstruct [:name, :label, :search, min_length: 1, limit: 20, async: false]

  @doc "Builds a source. Raises `ArgumentError` for options that are not valid."
  @spec new(atom() | String.t(), function() | keyword()) :: t()
  def new(name, fun) when is_function(fun), do: new(name, search: fun)

  def new(name, opts) when (is_atom(name) or is_binary(name)) and is_list(opts) do
    check_options!(name, opts)
    search = opts[:search]
    name = to_string(name)

    source = %__MODULE__{
      name: name,
      label: Keyword.get_lazy(opts, :label, fn -> Phoenix.Naming.humanize(name) end),
      search: search,
      min_length: Keyword.get(opts, :min_length, 1),
      limit: Keyword.get(opts, :limit, 20),
      async: opts[:async] == true
    }

    check!(source)
  end

  def new(name, _opts), do: invalid!(name, "a source is a function or a keyword list")

  defp check_options!(name, opts) do
    case Enum.find(Keyword.keys(opts), &(&1 not in @options)) do
      nil -> :ok
      key -> invalid!(name, "unknown option #{inspect(key)}")
    end

    unless is_function(opts[:search], 1) or is_function(opts[:search], 2),
      do: invalid!(name, ":search must be a function of the query (and the socket)")

    unless String.match?(to_string(name), ~r/\A[A-Za-z0-9_-]{1,64}\z/),
      do: invalid!(name, "a name has letters, digits, _ and - only")
  end

  defp check!(source) do
    cond do
      not is_binary(source.label) -> invalid!(source.name, ":label must be a string")
      source.min_length not in 0..200 -> invalid!(source.name, ":min_length must be 0 to 200")
      source.limit not in 1..100 -> invalid!(source.name, ":limit must be 1 to 100")
      true -> source
    end
  end

  @doc false
  # Runs a search callback and turns its results into actions: `{:ok,
  # actions}`, or `:error` when the callback fails. The ids get `prefix`.
  @spec run(function(), String.t(), term(), String.t() | nil, pos_integer(), map()) ::
          {:ok, [Action.t()]} | :error
  def run(fun, query, context, prefix, limit, metadata) do
    :telemetry.span([:jumon, :search], Map.put(metadata, :query, query), fn ->
      result = call(fun, query, context, prefix, limit)
      {result, Map.merge(metadata, %{query: query, result: elem_or(result)})}
    end)
  end

  defp elem_or({:ok, actions}), do: length(actions)
  defp elem_or(:error), do: :error

  defp call(fun, query, context, prefix, limit) do
    results = if is_function(fun, 1), do: fun.(query), else: fun.(query, context)

    if is_list(results) do
      {:ok, results |> Enum.flat_map(&coerce(&1, prefix)) |> Enum.take(limit)}
    else
      require Logger
      Logger.warning("Jumon: a search returned #{inspect(results)}, not a list")
      :error
    end
  rescue
    exception ->
      require Logger

      Logger.warning(
        "Jumon: a search failed: " <> Exception.format(:error, exception, __STACKTRACE__)
      )

      :error
  catch
    kind, reason ->
      require Logger
      Logger.warning("Jumon: a search failed: " <> Exception.format(kind, reason, __STACKTRACE__))
      :error
  end

  defp coerce(item, prefix) do
    case Action.coerce(item) do
      nil -> []
      action when prefix == nil -> [action]
      action -> [prefix_ids(action, prefix)]
    end
  end

  defp prefix_ids(action, prefix) do
    %{
      action
      | id: prefix <> action.id,
        source: String.trim_trailing(prefix, ":"),
        children: Enum.map(action.children, &prefix_ids(&1, prefix))
    }
  end

  defp invalid!(name, message) do
    raise ArgumentError, "Jumon: the source #{inspect(name)}: #{message}"
  end
end
