defmodule Jumon do
  @moduledoc """
  Jumon (呪文) adds a command palette to a Phoenix app.

  It ships a prebuilt palette bundle, the component that renders it, and
  the LiveView hooks that run its actions on the server, so that a Phoenix
  app gets a ⌘K palette with no Node.js build step of its own.

  Start with the [Quickstart](quickstart.md), then the [Actions](actions.md)
  and [Searching](searching.md) guides. The main modules are `Jumon.Commands` (the
  actions of an app), `Jumon.Components` (the palette), `Jumon.Live` (the
  LiveView hooks), `Jumon.History` (what each person runs) and `Jumon.Test`
  (the test helpers).
  """

  @external_resource "mix.exs"
  @version Mix.Project.config()[:version]

  @doc """
  Builds an action of the palette: `id` is unique in the palette, `name` is
  what it shows. See `Jumon.Action` for the options.

  ## Examples

      iex> Jumon.action(:home, "Home", navigate: "/").name
      "Home"

  """
  @spec action(atom() | String.t() | integer(), String.t(), keyword()) :: Jumon.Action.t()
  defdelegate action(id, name, opts \\ []), to: Jumon.Action, as: :new

  @doc """
  Returns the current Jumon version.

  ## Examples

      iex> Jumon.version()
      "#{@version}"

  """
  @spec version() :: String.t()
  def version, do: @version
end
