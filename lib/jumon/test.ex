defmodule Jumon.Test do
  @moduledoc """
  Helpers for `Phoenix.LiveViewTest`, to test the palette of a LiveView
  with no browser.

      import Jumon.Test

      test "finds and closes an issue", %{conn: conn} do
        {:ok, view, _html} = live(conn, ~p"/issues/42")

        assert "Close this issue" in names(search(view, "close"))
        assert %{"ok" => true} = run(view, "close_issue")
        assert render(view) =~ "Closed"
      end

  `search/3` returns what the palette would show for a query: the actions
  that match, ranked as the browser ranks them (`Jumon.Match`), then the
  results of the sources, which it asks the LiveView for as the palette
  does (waiting for the sources that run in a task). `run/3` runs an
  action on the server, as a choice in the palette does: the LiveView
  checks it and its arguments the same way.

  The functions take the palette's id as `:id` (`"jumon"` by default).
  """

  @compile {:no_warn_undefined, [LazyHTML]}

  import ExUnit.Assertions

  alias Phoenix.LiveViewTest

  @doc """
  The actions of the palette, as the browser has them (maps with string
  keys), each followed by its children.
  """
  @spec actions(struct(), keyword()) :: [map()]
  def actions(view, opts \\ []) do
    config(view, opts)["actions"]
  end

  @doc """
  Searches the palette as a person typing `query` in its box would, and
  returns the results in order: the actions (those without a parent, or
  any action for a non-empty query), then the results of each source.
  Each result is a map with string keys, with `"source"` for the results
  of a source.

  Options: `:id`, and `:timeout`, how long to wait for a source that runs
  in a task (1000 ms).
  """
  @spec search(struct(), String.t(), keyword()) :: [map()]
  def search(view, query, opts \\ []) when is_binary(query) do
    config = config(view, opts)

    local =
      config["actions"]
      |> Enum.reject(&(&1["hidden"] && &1["parent"] == nil))
      |> Enum.filter(&(String.trim(query) != "" or &1["parent"] == nil))
      |> Jumon.Match.rank(query)
      |> Enum.map(&elem(&1, 0))

    length = query |> String.trim() |> String.length()

    remote =
      if Enum.any?(config["sources"], &(length >= &1["minLength"])) do
        reply = event(view, "jumon:search", %{"query" => query}, opts)
        ref = reply["ref"]

        async =
          for source <- reply["pending"], into: %{} do
            timeout = Keyword.get(opts, :timeout, 1000)

            payload =
              receive_push(view, "jumon:results", %{"ref" => ref, "source" => source}, timeout)

            {source, payload["results"] || []}
          end

        results = Map.merge(reply["results"], async)

        Enum.flat_map(config["sources"], fn source ->
          Map.get(results, source["name"], [])
        end)
      else
        []
      end

    local ++ remote
  end

  @doc ~S|The names of results, for an assertion: `assert "Home" in names(search(view, "ho"))`.|
  @spec names([map()]) :: [String.t()]
  def names(results), do: Enum.map(results, & &1["name"])

  @doc """
  Searches the values of an argument of type `:search`, as the palette does
  on the argument's page, and returns them.
  """
  @spec search_arg(struct(), String.t(), atom() | String.t(), String.t(), keyword()) :: [map()]
  def search_arg(view, action_id, arg, query, opts \\ []) do
    reply =
      event(
        view,
        "jumon:search",
        %{"query" => query, "action" => to_string(action_id), "arg" => to_string(arg)},
        opts
      )

    case reply do
      %{"pending" => ["_arg"], "ref" => ref} ->
        payload =
          receive_push(
            view,
            "jumon:results",
            %{"ref" => ref, "source" => "_arg"},
            Keyword.get(opts, :timeout, 1000)
          )

        payload["results"] || []

      reply ->
        get_in(reply, ["results", "_arg"]) || []
    end
  end

  @doc """
  Runs an action of the palette on the server, as choosing it does, with
  the values of its arguments by name, and returns the reply:
  `%{"ok" => true}`, or `%{"error" => reason}` (`"unknown"`, `"disabled"`,
  `"forbidden"`, `"invalid"` with the `"arg"`, or `"message"` with the
  `"message"` the action returned).

  Only an action with `:run` runs on the server; the others run in the
  browser, and give `"unknown"` here.
  """
  @spec run(struct(), atom() | String.t(), map(), keyword()) :: map()
  def run(view, id, args \\ %{}, opts \\ []) do
    args = Map.new(args, fn {key, value} -> {to_string(key), value} end)
    event(view, "jumon:run", %{"id" => to_string(id), "args" => args}, opts)
  end

  defp config(view, opts) do
    id = Keyword.get(opts, :id, "jumon")
    html = view |> LiveViewTest.render() |> LazyHTML.from_fragment()
    palette = LazyHTML.query_by_id(html, id)

    case LazyHTML.attribute(palette, "data-config") do
      [json] -> JSON.decode!(json)
      _none -> flunk("Jumon.Test: no palette with the id #{inspect(id)}")
    end
  end

  defp event(view, event, params, opts) do
    id = Keyword.get(opts, :id, "jumon")
    ref = System.unique_integer([:positive])

    view
    |> LiveViewTest.element("##{id}")
    |> LiveViewTest.render_hook(event, Map.merge(%{"v" => 1, "ref" => ref}, params))

    %{proxy: {proxy_ref, _topic, _pid}} = view
    assert_receive {^proxy_ref, {:reply, %{"ref" => ^ref} = reply}}
    reply
  end

  defp receive_push(view, event, match, timeout) do
    %{proxy: {proxy_ref, _topic, _pid}} = view
    %{"ref" => ref, "source" => source} = match

    receive do
      {^proxy_ref, {:push_event, ^event, %{"ref" => ^ref, "source" => ^source} = payload}} ->
        payload
    after
      timeout ->
        flunk("Jumon.Test: the source #{match["source"]} gave no results in #{timeout} ms")
    end
  end
end
