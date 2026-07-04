defmodule BacViewWeb.SearchQueryTest do
  use ExUnit.Case, async: true

  alias BacViewWeb.SearchQuery

  test "parse keeps plain text as a single substring match" do
    assert SearchQuery.parse("wwsg temp") == %{
             include: ["wwsg temp"],
             exclude: [],
             mode: :substring
           }

    assert SearchQuery.parse("-unused") == %{
             include: [],
             exclude: ["unused"],
             mode: :tokens
           }
  end

  test "parse treats \\- as a literal leading minus" do
    assert SearchQuery.parse("\\-unused") == %{
             include: ["-unused"],
             exclude: [],
             mode: :tokens
           }
  end

  test "parse treats \\- tokens as include terms alongside exclusions" do
    assert SearchQuery.parse("analog \\-unused") == %{
             include: ["analog", "-unused"],
             exclude: [],
             mode: :tokens
           }

    assert SearchQuery.parse("analog \\-unused -spare") == %{
             include: ["analog", "-unused"],
             exclude: ["spare"],
             mode: :tokens
           }
  end

  test "matches? supports include and exclude tokens" do
    haystack = "analog input room sensor"

    assert SearchQuery.haystack_matches?("temp", "analog input temp room")
    refute SearchQuery.haystack_matches?("-temp", "analog input temp room")
    assert SearchQuery.haystack_matches?("analog -unused", haystack)
    refute SearchQuery.haystack_matches?("analog -room", haystack)
  end
end
