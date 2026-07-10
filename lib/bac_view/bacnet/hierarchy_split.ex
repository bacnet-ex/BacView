defmodule BacView.BACnet.HierarchySplit do
  @moduledoc false

  @delimiter_prefix "delimiter,"
  @positions_prefix "positions,"
  @all_special_id "all"
  @space_id "space"

  @delimiter_chars [
    " ",
    "!",
    "\"",
    "#",
    "$",
    "%",
    "&",
    "'",
    "(",
    ")",
    "*",
    "+",
    ",",
    "-",
    ".",
    "/",
    ":",
    ";",
    "<",
    "=",
    ">",
    "?",
    "@",
    "[",
    "\\",
    "]",
    "^",
    "_",
    "`",
    "{",
    "|",
    "}",
    "~"
  ]

  @type delimiter :: String.t() | :all_special
  @type t :: {:delimiter, delimiter()} | {:positions, [pos_integer()]}
  @type delimiter_option :: %{id: String.t(), char: delimiter()}

  @spec normalize(nil | String.t()) :: t() | nil
  def normalize(nil), do: nil
  def normalize(""), do: nil

  def normalize(value) when is_binary(value) do
    cond do
      String.starts_with?(value, @delimiter_prefix) ->
        id = String.slice(value, String.length(@delimiter_prefix)..-1//1)

        case delimiter_from_id(id) do
          nil -> nil
          delim -> {:delimiter, delim}
        end

      String.starts_with?(value, @positions_prefix) ->
        rest = String.slice(value, String.length(@positions_prefix)..-1//1)
        positions = parse_positions(rest)
        if positions != [], do: {:positions, positions}

      true ->
        nil
    end
  end

  def normalize(_value), do: nil

  @spec encode(t() | nil) :: String.t() | nil
  def encode({:delimiter, delim}) do
    case delimiter_id(delim) do
      nil -> nil
      id -> "#{@delimiter_prefix}#{id}"
    end
  end

  def encode({:positions, positions}) when is_list(positions) and positions != [] do
    "#{@positions_prefix}#{Enum.join(positions, ",")}"
  end

  def encode(nil), do: nil
  def encode(_split), do: nil

  @spec delimiter_options() :: [delimiter_option()]
  def delimiter_options() do
    [%{id: @all_special_id, char: :all_special}] ++
      Enum.map(@delimiter_chars, fn char ->
        %{id: delimiter_id(char), char: char}
      end)
  end

  @spec valid_delimiters() :: [String.t()]
  def valid_delimiters(), do: Enum.map(delimiter_options(), & &1.id)

  @spec delimiter_id(delimiter()) :: String.t() | nil
  def delimiter_id(:all_special), do: @all_special_id
  def delimiter_id(" "), do: @space_id
  def delimiter_id(char) when is_binary(char) and byte_size(char) == 1, do: char
  def delimiter_id(_char), do: nil

  @spec delimiter_from_id(String.t()) :: delimiter() | nil
  def delimiter_from_id(@all_special_id), do: :all_special
  def delimiter_from_id(@space_id), do: " "
  def delimiter_from_id(id) when id in @delimiter_chars, do: id
  def delimiter_from_id(_id), do: nil

  @spec parse_form(map()) :: t() | nil
  def parse_form(%{"mode" => "delimiter", "delimiter" => id}) when is_binary(id) do
    case delimiter_from_id(id) do
      nil -> nil
      delim -> {:delimiter, delim}
    end
  end

  def parse_form(%{"mode" => "positions", "positions" => positions})
      when is_binary(positions) do
    parsed = parse_positions(positions)
    if parsed != [], do: {:positions, parsed}
  end

  def parse_form(_params), do: nil

  @spec delimiter_label(delimiter()) :: String.t()
  def delimiter_label(:all_special), do: "all"

  def delimiter_label(" "), do: "space"

  def delimiter_label(char) when is_binary(char), do: char

  defp parse_positions(value) when is_binary(value) do
    segments =
      value
      |> String.split(",", trim: true)
      |> Enum.map(fn segment ->
        case Integer.parse(String.trim(segment)) do
          {n, ""} when n > 0 -> {:ok, n}
          _segment -> :error
        end
      end)

    case segments do
      [] ->
        []

      _segments ->
        if Enum.all?(segments, &match?({:ok, _}, &1)) do
          Enum.map(segments, fn {:ok, n} -> n end)
        else
          []
        end
    end
  end
end
