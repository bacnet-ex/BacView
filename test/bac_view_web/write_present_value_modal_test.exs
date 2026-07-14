defmodule BacViewWeb.WritePresentValueModalTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BacViewWeb.WritePresentValueModal

  defp multistate_object(overrides \\ %{}) do
    Map.merge(
      %{
        name: "MSV-1",
        type: :multi_state_value,
        instance: 1,
        writable: true,
        commandable: false,
        present_value: 2,
        present_value_formatted: "2 (On)",
        number_of_states: 2,
        state_text: ["Off", "On"]
      },
      overrides
    )
  end

  defp render_modal(object, assigns \\ %{}) do
    render_component(
      &WritePresentValueModal.modal/1,
      Map.merge(
        %{
          object: object,
          write_priority: 8,
          writing: false,
          locale: "de",
          locale_version: 0
        },
        assigns
      )
    )
  end

  test "renders multistate dropdown for in-range present value" do
    html = render_modal(multistate_object())

    assert html =~ ~s(id="modal-write-value")
    assert html =~ ~s(<select)
    assert html =~ "1 (Off)"
    assert html =~ "2 (On)"
    refute html =~ ~s(type="text" name="value")
  end

  test "renders multistate dropdown when present value is out of range" do
    html =
      render_modal(
        multistate_object(%{
          present_value: 0,
          present_value_formatted: "0"
        })
      )

    assert html =~ ~s(<select)
    assert html =~ "1 (Off)"
    assert html =~ "2 (On)"
    refute html =~ ~s(type="text" name="value")
    refute html =~ ~s(selected)
  end

  test "renders text input for non-multistate writable values" do
    html =
      render_modal(%{
        name: "AI-1",
        type: :analog_input,
        instance: 1,
        writable: true,
        commandable: false,
        present_value: 21.5,
        present_value_formatted: "21.5"
      })

    assert html =~ ~s(type="text")
    refute html =~ ~s(<select id="modal-write-value")
  end
end
