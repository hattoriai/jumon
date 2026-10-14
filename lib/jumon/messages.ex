defmodule Jumon.Messages do
  @moduledoc """
  The words of the palette: its labels, hints, the headings it gives
  itself ("Recent"), and the announcements for screen readers.

  The names of your actions and sections are yours (translate them as the
  rest of your app, with Gettext). The palette's own words are here, in
  English, Portuguese, Spanish, French, German, Italian, Dutch and
  Japanese; a locale with a region (`pt-BR`, `en-GB`) takes the words of
  its language, and another language gets English.

  Give the palette other words with `messages`, a map from the keys of
  `keys/0` to the new words, for example your own Gettext translations:

      <Jumon.Components.command_palette jumon={@jumon} messages={%{"placeholder" => gettext("Search")}} />

  Or set them for every palette in the config:

      config :jumon, messages: %{"fr" => %{"placeholder" => "Que voulez-vous faire ?"}}

  A word may have placeholders in braces (`{n}`, `{name}`), which the
  palette fills. The keys that end in `One` and `Other` are the plural
  forms of a count, picked with the plural rules of the locale.
  """

  alias Jumon.Messages.Translations

  @doc """
  Returns the keys of the messages.

  ## Examples

      iex> "placeholder" in Jumon.Messages.keys()
      true

  """
  @spec keys() :: [String.t()]
  def keys, do: Map.keys(Translations.english())

  @doc """
  Returns the languages with built-in words.

  ## Examples

      iex> Jumon.Messages.languages()
      ["de", "en", "es", "fr", "it", "ja", "nl", "pt"]

  """
  @spec languages() :: [String.t()]
  def languages, do: Translations.all() |> Map.keys() |> Enum.sort()

  @doc """
  The words for a locale: the built-in words of its language, then the
  words of the config for the locale and for its language, then
  `overrides`. Every key has a value (English when a language lacks one).

  Raises `ArgumentError` for an override with an unknown key, so that a
  typo shows.

  ## Examples

      iex> Jumon.Messages.for_locale("pt-PT")["recent"]
      "Recentes"
      iex> Jumon.Messages.for_locale("sv")["recent"]
      "Recent"
      iex> Jumon.Messages.for_locale("en", %{"recent" => "Lately"})["recent"]
      "Lately"

  """
  @spec for_locale(String.t(), map()) :: %{String.t() => String.t()}
  def for_locale(locale, overrides \\ %{}) when is_binary(locale) do
    language = language(locale)
    config = Application.get_env(:jumon, :messages, %{})

    Translations.english()
    |> Map.merge(Map.get(Translations.all(), language, %{}))
    |> Map.merge(stringify(Map.get(config, language, %{})))
    |> Map.merge(stringify(Map.get(config, locale, %{})))
    |> Map.merge(check!(stringify(overrides || %{})))
  end

  @doc """
  The language of a locale: `"pt"` for `"pt-BR"`, `"zh"` for `"zh_Hant"`.

  ## Examples

      iex> Jumon.Messages.language("pt-BR")
      "pt"

  """
  @spec language(String.t()) :: String.t()
  def language(locale) do
    locale |> String.split(["-", "_"], parts: 2) |> hd() |> String.downcase()
  end

  defp stringify(map) when is_map(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)

  defp check!(overrides) do
    english = Translations.english()

    case Enum.reject(Map.keys(overrides), &Map.has_key?(english, &1)) do
      [] ->
        overrides

      unknown ->
        raise ArgumentError,
              "Jumon.Messages: unknown message keys #{inspect(unknown)}; see Jumon.Messages.keys/0"
    end
  end
end
