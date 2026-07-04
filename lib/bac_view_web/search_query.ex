defmodule BacViewWeb.SearchQuery do
  @moduledoc false

  @type t :: %{
          include: [String.t()],
          exclude: [String.t()],
          mode: :all | :substring | :tokens
        }

  @spec parse(String.t()) :: t()
  def parse(""), do: %{include: [], exclude: [], mode: :all}

  def parse(search) when is_binary(search) do
    trimmed = String.trim(search)

    cond do
      trimmed == "" ->
        %{include: [], exclude: [], mode: :all}

      exclusion_syntax?(trimmed) ->
        parse_tokenized_search(trimmed)

      true ->
        %{include: [unescape_search_term(trimmed)], exclude: [], mode: :substring}
    end
  end

  @spec matches?(t(), String.t()) :: boolean()
  def matches?(%{mode: :all}, _haystack), do: true

  def matches?(%{mode: :substring, include: [term]}, haystack) do
    String.contains?(haystack, String.downcase(term))
  end

  def matches?(%{mode: :tokens, include: include, exclude: exclude}, haystack) do
    include_ok =
      include == [] or
        Enum.all?(include, &String.contains?(haystack, String.downcase(&1)))

    exclude_ok =
      Enum.all?(exclude, &(not String.contains?(haystack, String.downcase(&1))))

    include_ok and exclude_ok
  end

  @spec haystack_matches?(String.t(), String.t()) :: boolean()
  def haystack_matches?(search, haystack) when is_binary(search) and is_binary(haystack) do
    search
    |> parse()
    |> matches?(String.downcase(haystack))
  end

  defp exclusion_syntax?(search) do
    unescaped_leading_minus?(search) or
      Regex.match?(~r/(?:^|\s)-(?<!\\)\S/, search) or
      Regex.match?(~r/(?:^|\s)\\-\S/, search)
  end

  defp unescaped_leading_minus?(""), do: false

  defp unescaped_leading_minus?(search) do
    String.starts_with?(search, "-") and not String.starts_with?(search, "\\-")
  end

  defp parse_tokenized_search(search) do
    search
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reduce(%{include: [], exclude: []}, fn token, acc ->
      case classify_search_token(token) do
        :ignore -> acc
        {:include, term} -> %{acc | include: [term | acc.include]}
        {:exclude, term} -> %{acc | exclude: [term | acc.exclude]}
      end
    end)
    |> then(fn %{include: include, exclude: exclude} ->
      %{include: Enum.reverse(include), exclude: Enum.reverse(exclude), mode: :tokens}
    end)
  end

  defp classify_search_token(token) do
    cond do
      String.starts_with?(token, "\\-") ->
        {:include, unescape_search_term(token)}

      String.starts_with?(token, "-") and byte_size(token) > 1 ->
        {:exclude, String.slice(token, 1..-1//1)}

      String.starts_with?(token, "-") ->
        :ignore

      true ->
        {:include, token}
    end
  end

  defp unescape_search_term(term), do: String.replace(term, "\\-", "-")
end
