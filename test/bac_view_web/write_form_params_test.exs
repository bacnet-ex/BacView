defmodule BacViewWeb.WriteFormParamsTest do
  use ExUnit.Case, async: true

  alias BacViewWeb.WriteFormParams

  test "unwraps nested write form params" do
    params = %{
      "write" => %{
        "property" => "present_value",
        "value" => "21.5",
        "priority" => "5"
      }
    }

    assert WriteFormParams.normalize(params) == params["write"]
    assert WriteFormParams.priority(params, 8) == 5
  end

  test "reads flat form params" do
    params = %{"property" => "present_value", "value" => "1.0", "priority" => "12"}

    assert WriteFormParams.normalize(params) == params
    assert WriteFormParams.priority(params, 8) == 12
  end

  test "falls back to default priority" do
    assert WriteFormParams.priority(%{"property" => "present_value"}, 8) == 8
  end

  test "reads priority from phx-value on reset events" do
    assert WriteFormParams.priority(%{"property" => "present_value", "priority" => "3"}, 8) == 3
  end
end
