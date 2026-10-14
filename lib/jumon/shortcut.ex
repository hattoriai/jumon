defmodule Jumon.Shortcut do
  @moduledoc """
  Keyboard shortcuts, as an action's `:shortcut` gives them.

  A shortcut is a string of one or more chords, separated by spaces, pressed
  one after the other: `"mod+k"`, `"shift+?"`, `"g h"` (press `g`, then `h`).
  A chord is its modifiers and one key, joined by `+`:

    * the modifiers are `mod` (⌘ on Apple devices, Ctrl elsewhere), `ctrl`,
      `alt` (also `option`), `shift` and `meta` (also `cmd`);
    * the key is a letter, a digit, a punctuation character, or one of
      `enter`, `escape`, `backspace`, `delete`, `tab`, `space`, `up`,
      `down`, `left`, `right`, `home`, `end`, `pageup`, `pagedown` and `f1`
      to `f12`.

  A shortcut is normalized to lower case, with its modifiers in the order
  `mod`, `ctrl`, `alt`, `shift`, `meta`: `"Shift+Mod+P"` is `"mod+shift+p"`.
  The browser reads the same form.
  """

  @modifiers ~w(mod ctrl alt shift meta)
  @aliases %{
    "cmd" => "meta",
    "command" => "meta",
    "option" => "alt",
    "opt" => "alt",
    "control" => "ctrl",
    "esc" => "escape",
    "return" => "enter",
    "arrowup" => "up",
    "arrowdown" => "down",
    "arrowleft" => "left",
    "arrowright" => "right",
    "del" => "delete"
  }
  @named ~w(enter escape backspace delete tab space up down left right home end pageup pagedown) ++
           Enum.map(1..12, &"f#{&1}")

  @doc """
  Normalizes a shortcut. Returns `{:ok, shortcut}` or `:error`.

  ## Examples

      iex> Jumon.Shortcut.normalize("Shift+Mod+P")
      {:ok, "mod+shift+p"}
      iex> Jumon.Shortcut.normalize("g  h")
      {:ok, "g h"}
      iex> Jumon.Shortcut.normalize("mod+")
      :error

  """
  @spec normalize(String.t()) :: {:ok, String.t()} | :error
  def normalize(shortcut) when is_binary(shortcut) do
    chords = String.split(shortcut, ~r/\s+/, trim: true)

    if chords == [] or length(chords) > 4, do: :error, else: chords(chords, [])
  end

  def normalize(_shortcut), do: :error

  defp chords([], acc), do: {:ok, acc |> Enum.reverse() |> Enum.join(" ")}

  defp chords([chord | rest], acc) do
    case chord(chord) do
      {:ok, chord} -> chords(rest, [chord | acc])
      :error -> :error
    end
  end

  @doc """
  Normalizes a shortcut, and raises `ArgumentError` when it is not valid.
  """
  @spec normalize!(String.t()) :: String.t()
  def normalize!(shortcut) do
    case normalize(shortcut) do
      {:ok, normalized} ->
        normalized

      :error ->
        raise ArgumentError,
              "Jumon: #{inspect(shortcut)} is not a shortcut, see Jumon.Shortcut for the form"
    end
  end

  # "+" alone, or as the last part ("shift++"), is the plus key.
  defp chord(chord) do
    parts =
      case String.split(String.downcase(chord), "+") do
        ["", ""] -> ["+"]
        parts when length(parts) > 2 -> plus_key(parts)
        parts -> parts
      end

    {modifiers, [key]} = Enum.split(Enum.map(parts, &Map.get(@aliases, &1, &1)), -1)

    cond do
      key == "" or Enum.any?(modifiers, &(&1 not in @modifiers)) -> :error
      length(Enum.uniq(modifiers)) != length(modifiers) -> :error
      not key?(key) -> :error
      true -> {:ok, Enum.join(Enum.filter(@modifiers, &(&1 in modifiers)) ++ [key], "+")}
    end
  end

  defp plus_key(parts) do
    case Enum.split(parts, -2) do
      {modifiers, ["", ""]} -> modifiers ++ ["+"]
      _other -> parts
    end
  end

  defp key?(key) when key in @named, do: true
  defp key?(key), do: String.length(key) == 1 and not String.match?(key, ~r/\s/u)
end
