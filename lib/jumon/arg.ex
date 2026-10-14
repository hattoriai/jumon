defmodule Jumon.Arg do
  @moduledoc """
  A value that an action asks for before it runs: "Assign to…" asks for a
  person, "Rename…" for a name. The palette asks for each argument of an
  action in turn, on a page with the action's name as its breadcrumb, and
  then calls the action's `:run` with the values:

      action(:assign, "Assign to…",
        args: [
          person: [search: &MyApp.People.search/2, placeholder: "Assign to whom?"],
          note: [type: :text, placeholder: "A note (optional)", optional: true]
        ],
        run: fn %{person: person_id, note: note}, socket -> ... end
      )

  See the [Arguments](arguments.md) guide.

  ## Kinds

    * `:choice` - one of a list of `:options` (actions, maps with `:id`
      and `:name`, or `{id, name}` tuples), which the palette filters as
      the person types. The default kind when `:options` are given.
    * `:search` - one of the results of `:search`, a function of the query,
      or of the query and the socket, that returns the same kinds of items.
      The default kind when `:search` is given.
    * `:text` - the text the person types. The default kind otherwise.

  ## Options

    * `:type` - `:choice`, `:search` or `:text`.
    * `:label` - the name of the value, in the breadcrumb once it is chosen
      ("Person"). The default is the argument's name in words.
    * `:placeholder` - the words in the empty box.
    * `:options`, `:search` - see above.
    * `:async` - for `:search`, `true` to run the search in a task of the
      LiveView, so that a slow one does not block it.
    * `:min_length` - for `:search`, the characters of the query before the
      first search (default 0).
    * `:max_length` - for `:text`, the longest text (default 500).
    * `:optional` - for `:text`, `true` to take an empty text (as `nil`).
    * `:validate` - a function of the value (and the socket) that returns
      `:ok`, `{:ok, value}` or `{:error, message}`; the message is shown in
      the palette, which asks again.

  The values reach `:run` in a map keyed by the arguments' names: the id of
  the chosen option or result (as a string), or the text. The server checks
  each one again before `:run` gets it: a choice must be one of the
  options, a result one of the results that the search gave this person,
  a text a string of at most `:max_length` characters.
  """

  alias Jumon.Action

  @types [:text, :choice, :search]
  @options [
    :type,
    :label,
    :placeholder,
    :options,
    :search,
    :async,
    :min_length,
    :max_length,
    :optional,
    :validate
  ]

  @type t :: %__MODULE__{
          name: atom(),
          type: :text | :choice | :search,
          label: String.t(),
          placeholder: String.t() | nil,
          options: [Action.t()],
          search: function() | nil,
          async: boolean(),
          min_length: non_neg_integer(),
          max_length: pos_integer(),
          optional: boolean(),
          validate: function() | nil
        }

  @enforce_keys [:name, :type, :label]
  defstruct [
    :name,
    :type,
    :label,
    :placeholder,
    :search,
    :validate,
    options: [],
    async: false,
    min_length: 0,
    max_length: 500,
    optional: false
  ]

  @doc """
  Builds an argument. Raises `ArgumentError` for options that are not
  valid.
  """
  @spec new(atom(), keyword()) :: t()
  def new(name, opts) when is_atom(name) and is_list(opts) do
    case Enum.find(Keyword.keys(opts), &(&1 not in @options)) do
      nil -> :ok
      key -> invalid!(name, "unknown option #{inspect(key)}")
    end

    type = type!(name, opts)

    %__MODULE__{
      name: name,
      type: type,
      label: Keyword.get_lazy(opts, :label, fn -> Phoenix.Naming.humanize(name) end),
      placeholder: opts[:placeholder],
      options: options!(name, type, opts[:options]),
      search: search!(name, type, opts[:search]),
      async: opts[:async] == true,
      min_length: Keyword.get(opts, :min_length, 0),
      max_length: Keyword.get(opts, :max_length, 500),
      optional: opts[:optional] == true,
      validate: validate!(name, opts[:validate])
    }
    |> check!()
  end

  def new(name, _opts), do: invalid!(name, "an argument is a name and a keyword list of options")

  defp type!(name, opts) do
    type =
      cond do
        Keyword.has_key?(opts, :type) -> opts[:type]
        Keyword.has_key?(opts, :options) -> :choice
        Keyword.has_key?(opts, :search) -> :search
        true -> :text
      end

    if type in @types, do: type, else: invalid!(name, ":type must be one of #{inspect(@types)}")
  end

  defp options!(_name, :choice, options) when is_list(options) do
    Enum.map(options, fn option ->
      Action.coerce(option) ||
        raise ArgumentError, "Jumon: the option #{inspect(option)} is not an item"
    end)
  end

  defp options!(name, :choice, _options), do: invalid!(name, "a :choice needs a list of :options")
  defp options!(_name, _type, nil), do: []
  defp options!(name, _type, _options), do: invalid!(name, ":options go with type: :choice")

  defp search!(_name, :search, fun) when is_function(fun, 1) or is_function(fun, 2), do: fun

  defp search!(name, :search, _fun),
    do: invalid!(name, "a :search needs a function of the query (and the socket)")

  defp search!(_name, _type, nil), do: nil
  defp search!(name, _type, _fun), do: invalid!(name, ":search goes with type: :search")

  defp validate!(_name, nil), do: nil
  defp validate!(_name, fun) when is_function(fun, 1) or is_function(fun, 2), do: fun
  defp validate!(name, _fun), do: invalid!(name, ":validate must be a function of the value")

  defp check!(%__MODULE__{} = arg) do
    cond do
      not is_binary(arg.label) or arg.label == "" ->
        invalid!(arg.name, ":label must be a string")

      arg.placeholder != nil and not is_binary(arg.placeholder) ->
        invalid!(arg.name, ":placeholder must be a string")

      true ->
        check_lengths!(arg)
    end
  end

  defp check_lengths!(arg) do
    cond do
      not (is_integer(arg.min_length) and arg.min_length in 0..200) ->
        invalid!(arg.name, ":min_length must be an integer from 0 to 200")

      not (is_integer(arg.max_length) and arg.max_length in 1..100_000) ->
        invalid!(arg.name, ":max_length must be an integer from 1 to 100000")

      true ->
        arg
    end
  end

  @doc false
  # Checks a value that the browser sent for this argument; `offered` are
  # the ids that its search gave this socket.
  @spec cast(t(), term(), MapSet.t()) :: {:ok, term()} | {:error, :invalid}
  def cast(%__MODULE__{type: :text} = arg, value, _offered) do
    case value do
      nil when arg.optional ->
        {:ok, nil}

      text when is_binary(text) ->
        text = String.trim(text)

        cond do
          text == "" and arg.optional -> {:ok, nil}
          text == "" -> {:error, :invalid}
          String.length(text) > arg.max_length -> {:error, :invalid}
          true -> {:ok, text}
        end

      _other ->
        {:error, :invalid}
    end
  end

  def cast(%__MODULE__{type: :choice} = arg, value, _offered) when is_binary(value) do
    if Enum.any?(arg.options, &(&1.id == value)), do: {:ok, value}, else: {:error, :invalid}
  end

  def cast(%__MODULE__{type: :search}, value, offered) when is_binary(value) do
    if MapSet.member?(offered, value), do: {:ok, value}, else: {:error, :invalid}
  end

  def cast(_arg, _value, _offered), do: {:error, :invalid}

  @doc false
  @spec to_client(t()) :: map()
  def to_client(%__MODULE__{} = arg) do
    %{
      "name" => Atom.to_string(arg.name),
      "type" => Atom.to_string(arg.type),
      "label" => arg.label,
      "placeholder" => arg.placeholder,
      "options" => Enum.map(arg.options, &Action.to_client/1),
      "minLength" => arg.min_length,
      "maxLength" => arg.type == :text && arg.max_length,
      "optional" => arg.optional
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, false, [], 0] end)
    |> Map.new()
  end

  defp invalid!(name, message) do
    raise ArgumentError, "Jumon: the argument #{inspect(name)}: #{message}"
  end
end
