defmodule Jumon.Install.Edits do
  @moduledoc false
  # The edits of `mix jumon.install`, as pure functions on the source of
  # each file. Each edit returns:
  #
  #   * `{:changed, source}` - the new source,
  #   * `:unchanged` - the file already has everything,
  #   * `{:manual, text}` - the edit cannot be made safely; `text` tells
  #     the person what to add.

  @type result :: {:changed, String.t()} | :unchanged | {:manual, String.t()}

  @js_import ~s(import { Jumon } from "jumon")

  # The path from assets/css/ to the Jumon package, when it is in deps/.
  @package_dir "../../deps/jumon"

  ## assets/js/app.js

  @doc false
  @spec app_js(String.t()) :: result()
  def app_js(source) when is_binary(source) do
    # Any import that binds `Jumon`, from "jumon" or from another path.
    import? =
      Regex.match?(
        ~r/^import\s*(?:\{[^}]*\bJumon\b[^}]*\}|Jumon\b[^\n]*?)\s*from\s*["']/m,
        source
      )

    case hooks(source) do
      :error ->
        {:manual, app_js_manual(import?)}

      {:ok, with_hooks} ->
        new = if import?, do: with_hooks, else: add_js_import(with_hooks)
        if new == source, do: :unchanged, else: {:changed, new}
    end
  end

  @doc false
  @spec app_js_manual(boolean()) :: String.t()
  def app_js_manual(import? \\ false) do
    import_text =
      if import?, do: "", else: "Add the import to assets/js/app.js:\n\n    #{@js_import}\n\n"

    import_text <>
      """
      Add Jumon to the hooks of the LiveSocket in assets/js/app.js:

          const liveSocket = new LiveSocket("/live", Socket, {
            params: {_csrf_token: csrfToken},
            hooks: {...colocatedHooks, Jumon},
          })
      """
  end

  # After the line where the last top-level import statement ends (an
  # import can span several lines), else at the top.
  defp add_js_import(source) do
    code = mask(source)

    case Regex.scan(~r/^import(?=[\s{*"'])/m, code, return: :index) |> List.last() do
      nil ->
        @js_import <> "\n" <> source

      [{at, _length}] ->
        at = import_end(code, at)

        line_end =
          if newline = first_match(~r/\n/, rest(code, at)),
            do: at + elem(newline, 0),
            else: byte_size(code)

        splice(source, line_end, 0, "\n" <> @js_import)
    end
  end

  # The index after the module specifier of the import at `at`: its first
  # string, whose text the mask keeps as spaces between the quotes.
  defp import_end(code, at) do
    case Regex.run(~r/["']/, rest(code, at), return: :index) do
      [{open, 1}] ->
        quote_char = binary_part(code, at + open, 1)
        from = at + open + 1

        case :binary.match(code, quote_char, scope: {from, byte_size(code) - from}) do
          {close, 1} -> close + 1
          :nomatch -> byte_size(code)
        end

      nil ->
        byte_size(code)
    end
  end

  defp rest(code, at), do: binary_part(code, at, byte_size(code) - at)

  # Finds the `hooks` of the options of `new LiveSocket(...)`, and adds
  # `Jumon` to them. Returns `{:ok, source}` (the same source when Jumon
  # is already there) or `:error`.
  defp hooks(source) do
    code = mask(source)

    with {call, call_length} <- first_match(~r/\bnew\s+LiveSocket\s*\(/, code),
         open when is_integer(open) <- options_open(code, call + call_length),
         close when is_integer(close) <- close(code, open) do
      options = binary_part(code, open + 1, close - open - 1)

      top = top_level(options)

      cond do
        other_hooks_key?(source, open + 1, top) ->
          :error

        match = first_match(~r/(?<![\w$.])hooks\s*:\s*/, top) ->
          hooks_at(source, code, open, match)

        true ->
          {:ok, insert_hooks_key(source, open, options)}
      end
    else
      _other -> :error
    end
  end

  defp hooks_at(source, code, open, {at, length}),
    do: hooks_value(source, code, open + 1 + at + length)

  # A quoted `"hooks":` key, or the `hooks` shorthand, at the top level of
  # the options: the edit cannot see through it, so the person adds Jumon.
  defp other_hooks_key?(source, offset, top) do
    quoted =
      ~r/(["'])\s{5}\1\s*:/
      |> Regex.scan(top, return: :index)
      |> Enum.any?(fn [{at, _length} | _group] ->
        Regex.match?(~r/^["']hooks["']/, binary_part(source, offset + at, 7))
      end)

    quoted or Regex.match?(~r/(?:^|,)\s*hooks\s*(?:,|$)/, top)
  end

  # The first `{` among the arguments of the call, before its `)`.
  defp options_open(code, from), do: scan_to_brace(code, from, 0)

  defp scan_to_brace(code, at, _depth) when at >= byte_size(code), do: nil

  defp scan_to_brace(code, at, depth) do
    case :binary.at(code, at) do
      ?{ when depth == 0 -> at
      char when char in [?(, ?[, ?{] -> scan_to_brace(code, at + 1, depth + 1)
      ?) when depth == 0 -> nil
      char when char in [?), ?], ?}] -> scan_to_brace(code, at + 1, depth - 1)
      _char -> scan_to_brace(code, at + 1, depth)
    end
  end

  defp insert_hooks_key(source, open, options) do
    {text, replaced} =
      cond do
        String.trim(options) == "" ->
          {"hooks: {Jumon}", byte_size(options)}

        String.contains?(options, "\n") ->
          [_first, line | _rest] = String.split(options, "\n")
          [indent] = Regex.run(~r/^[ \t]*/, line)
          {"\n" <> indent <> "hooks: {Jumon},", 0}

        true ->
          {"hooks: {Jumon}, ", 0}
      end

    splice(source, open + 1, replaced, text)
  end

  defp hooks_value(source, code, at) do
    rest = binary_part(code, at, byte_size(code) - at)

    cond do
      String.starts_with?(rest, "{") ->
        close = close(code, at)
        inner = binary_part(source, at + 1, close - at - 1)

        if Regex.match?(~r/(?<![\w$.])Jumon\b/, binary_part(code, at + 1, close - at - 1)),
          do: {:ok, source},
          else: {:ok, splice(source, at + 1, close - at - 1, add_to_object(inner))}

      match = Regex.run(~r/^([A-Za-z_$][\w$]*)\s*(?=[,}\n])/, rest) ->
        [whole, name] = match

        if Regex.match?(
             ~r/\b#{Regex.escape(name)}\s*(\.\s*Jumon|\[\s*["']Jumon["']\s*\])\s*=/,
             code
           ),
           do: {:ok, source},
           else:
             {:ok,
              splice(source, at, byte_size(String.trim_trailing(whole)), "{...#{name}, Jumon}")}

      true ->
        :error
    end
  end

  defp add_to_object(inner) do
    trimmed = String.trim_trailing(inner)
    trailing = binary_part(inner, byte_size(trimmed), byte_size(inner) - byte_size(trimmed))

    cond do
      String.trim(inner) == "" ->
        "Jumon"

      String.contains?(inner, "\n") ->
        last = trimmed |> String.split("\n") |> List.last()
        [indent] = Regex.run(~r/^[ \t]*/, last)
        comma = if String.ends_with?(trimmed, ","), do: "", else: ","
        trimmed <> comma <> "\n" <> indent <> "Jumon," <> trailing

      String.ends_with?(trimmed, ",") ->
        trimmed <> " Jumon" <> trailing

      true ->
        trimmed <> ", Jumon" <> trailing
    end
  end

  defp splice(source, at, length, text) do
    binary_part(source, 0, at) <>
      text <>
      binary_part(source, at + length, byte_size(source) - at - length)
  end

  # Replaces the text of strings and comments with spaces, byte for byte,
  # so that the positions stay the same and brackets in them do not count.
  defp mask(source), do: source |> mask(:code, []) |> IO.iodata_to_binary()

  defp mask(<<>>, _state, acc), do: Enum.reverse(acc)
  defp mask(<<"//", rest::binary>>, :code, acc), do: mask(rest, :line, ["  " | acc])
  defp mask(<<"/*", rest::binary>>, :code, acc), do: mask(rest, :block, ["  " | acc])

  defp mask(<<q, rest::binary>>, :code, acc) when q in [?", ?', ?`],
    do: mask(rest, {:string, q}, [q | acc])

  defp mask(<<c, rest::binary>>, :code, acc), do: mask(rest, :code, [c | acc])
  defp mask(<<?\n, rest::binary>>, :line, acc), do: mask(rest, :code, [?\n | acc])
  defp mask(<<"*/", rest::binary>>, :block, acc), do: mask(rest, :code, ["  " | acc])
  defp mask(<<?\n, rest::binary>>, :block, acc), do: mask(rest, :block, [?\n | acc])

  defp mask(<<_c, rest::binary>>, state, acc) when state in [:line, :block],
    do: mask(rest, state, [?\s | acc])

  defp mask(<<?\\, _c, rest::binary>>, {:string, _q} = state, acc),
    do: mask(rest, state, ["  " | acc])

  defp mask(<<q, rest::binary>>, {:string, q}, acc), do: mask(rest, :code, [q | acc])
  defp mask(<<?\n, rest::binary>>, {:string, _q} = state, acc), do: mask(rest, state, [?\n | acc])
  defp mask(<<_c, rest::binary>>, {:string, _q} = state, acc), do: mask(rest, state, [?\s | acc])

  # The index of the bracket that closes the one at `open`, in masked code.
  defp close(code, open), do: close(code, open + 1, 1)
  defp close(code, at, _depth) when at >= byte_size(code), do: nil

  defp close(code, at, depth) do
    case :binary.at(code, at) do
      char when char in [?(, ?[, ?{] -> close(code, at + 1, depth + 1)
      char when char in [?), ?], ?}] and depth == 1 -> at
      char when char in [?), ?], ?}] -> close(code, at + 1, depth - 1)
      _char -> close(code, at + 1, depth)
    end
  end

  # Masked code with the text inside nested brackets replaced by spaces.
  defp top_level(code) do
    {chars, _depth} =
      code
      |> :binary.bin_to_list()
      |> Enum.map_reduce(0, fn
        char, depth when char in [?(, ?[, ?{] -> {if(depth == 0, do: char, else: ?\s), depth + 1}
        char, depth when char in [?), ?], ?}] -> {if(depth == 1, do: char, else: ?\s), depth - 1}
        ?\n, depth -> {?\n, depth}
        char, 0 -> {char, 0}
        _char, depth -> {?\s, depth}
      end)

    :binary.list_to_bin(chars)
  end

  defp first_match(regex, text) do
    case Regex.run(regex, text, return: :index) do
      [{at, length} | _groups] -> {at, length}
      nil -> nil
    end
  end

  ## assets/css/app.css

  @doc false
  @spec app_css(String.t(), String.t()) :: result()
  def app_css(source, dir \\ @package_dir) when is_binary(source) and is_binary(dir) do
    # The Sumi line comes only with the jumon.css import, so a person who
    # removed it does not get it back.
    if Regex.match?(~r/priv\/static\/jumon\.css/, source) do
      :unchanged
    else
      lines = String.split(source, "\n")

      added =
        if String.contains?(source, "jumon-sumi.css"),
          do: [css_import(dir)],
          else: [css_import(dir), sumi_import(dir)]

      {head, tail} = Enum.split(lines, css_insert_at(lines))
      {:changed, Enum.join(head ++ added ++ tail, "\n")}
    end
  end

  @doc false
  @spec app_css_manual(String.t()) :: String.t()
  def app_css_manual(dir \\ @package_dir) do
    """
    Add the palette style sheet to assets/css/app.css, and the Sumi theme if you want it:

        #{css_import(dir)}
        #{sumi_import(dir)}
    """
  end

  defp css_import(dir), do: ~s(@import "#{dir}/priv/static/jumon.css";)
  defp sumi_import(dir), do: ~s(/* @import "#{dir}/priv/static/jumon-sumi.css"; */)

  @doc """
  The path from the directory `from` to `path`, both absolute, with `..`
  where it must go up: the form an `@import` or a `Path.expand/2` in the
  app's files needs.
  """
  @spec relative(Path.t(), Path.t()) :: String.t()
  def relative(path, from),
    do: Path.relative_to(Path.expand(path), Path.expand(from), force: true)

  # After the last top-level @import, else after a @charset, else at the top.
  defp css_insert_at(lines) do
    case last_index(lines, &Regex.match?(~r/^@import\b/, &1)) do
      nil ->
        case last_index(lines, &Regex.match?(~r/^@charset\b/, &1)) do
          nil -> 0
          index -> index + 1
        end

      index ->
        index + 1
    end
  end

  ## config/config.exs, read for the esbuild note and never edited

  @doc false
  @spec node_path?(String.t()) :: boolean()
  def node_path?(config_source) do
    Regex.match?(~r/"NODE_PATH"\s*=>[^\n]*deps/, config_source)
  end

  @doc """
  Whether a `NODE_PATH` of the config has `Path.expand(dir, __DIR__)`, for
  a Jumon package outside deps/ (a path dependency).
  """
  @spec node_path?(String.t(), String.t()) :: boolean()
  def node_path?(config_source, dir) do
    Regex.match?(
      ~r/"NODE_PATH"\s*=>[^\n]*Path\.expand\(\s*"#{Regex.escape(dir)}"\s*,\s*__DIR__\s*\)/,
      config_source
    )
  end

  ## lib/my_app_web/commands.ex

  @doc false
  # The web module of an app: MyAppWeb for :my_app.
  @spec web_module(atom()) :: String.t()
  def web_module(app), do: Macro.camelize(Atom.to_string(app)) <> "Web"

  @doc false
  @spec commands_module(String.t()) :: String.t()
  def commands_module(web) do
    """
    defmodule #{web}.Commands do
      @moduledoc \"\"\"
      The actions of the command palette (⌘K), for each LiveView of the
      live_sessions that mount them with `{Jumon.Live, #{web}.Commands}`.
      See `Jumon.Commands`.
      \"\"\"
      use Jumon.Commands
      use #{web}, :verified_routes

      @impl true
      def actions(_socket) do
        [
          action(:home, "Home", navigate: ~p"/", section: "Go to", shortcut: "g h", icon: "hero-home")
        ]
      end
    end
    """
  end

  ## Diffs

  @doc false
  @spec diff(String.t(), String.t(), String.t()) :: String.t()
  def diff(path, old, new) do
    changes = List.myers_difference(String.split(old, "\n"), String.split(new, "\n"))
    last = length(changes) - 1

    lines =
      changes
      |> Enum.with_index()
      |> Enum.flat_map(fn
        {{:eq, lines}, index} -> context(lines, index == 0, index == last)
        {{:del, lines}, _index} -> Enum.map(lines, &("- " <> &1))
        {{:ins, lines}, _index} -> Enum.map(lines, &("+ " <> &1))
      end)

    Enum.join(["--- #{path}", "+++ #{path}" | lines], "\n") <> "\n"
  end

  # Two lines of context around each change.
  defp context(lines, first?, last?) do
    lines
    |> shown(first?, last?)
    |> Enum.map(fn
      :gap -> "  ..."
      line -> "  " <> line
    end)
  end

  defp shown(_lines, true, true), do: []

  defp shown(lines, true, false),
    do: if(length(lines) > 2, do: [:gap | Enum.take(lines, -2)], else: lines)

  defp shown(lines, false, true),
    do: if(length(lines) > 2, do: Enum.take(lines, 2) ++ [:gap], else: lines)

  defp shown(lines, false, false) when length(lines) <= 5, do: lines
  defp shown(lines, false, false), do: Enum.take(lines, 2) ++ [:gap | Enum.take(lines, -2)]

  defp last_index(list, fun) do
    list
    |> Enum.with_index()
    |> Enum.filter(fn {item, _index} -> fun.(item) end)
    |> List.last()
    |> case do
      nil -> nil
      {_item, index} -> index
    end
  end
end
