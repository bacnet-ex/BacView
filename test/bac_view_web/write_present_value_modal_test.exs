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

  test "hooks focus on the value field not the priority dropdown" do
    html =
      render_modal(
        multistate_object(%{
          commandable: true,
          present_value: 2
        })
      )

    assert html =~ ~s(id="write-present-value-modal")
    assert html =~ ~s(phx-hook="FocusFirstInput")
    assert html =~ ~s(id="modal-write-priority")
    assert html =~ ~s(id="modal-write-value")
    assert html =~ ~s(data-autofocus)
    # Priority select must not be the autofocus target.
    refute html =~ ~r/id="modal-write-priority"[^>]*data-autofocus/
    assert html =~ ~r/id="modal-write-value"[^>]*data-autofocus/
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
    assert html =~ ~s(id="modal-write-value")
    assert html =~ ~s(data-autofocus)
    refute html =~ ~s(<select id="modal-write-value")
  end

  test "renders binary dropdown with inactive/active text labels" do
    html =
      render_modal(%{
        name: "BV-1",
        type: :binary_value,
        instance: 1,
        writable: true,
        commandable: false,
        present_value: true,
        present_value_formatted: "Open",
        inactive_text: "Closed",
        active_text: "Open"
      })

    assert html =~ ~s(id="modal-write-value")
    assert html =~ ~s(value="true")
    assert html =~ ~s(value="false")
    assert html =~ "Open"
    assert html =~ "Closed"
    refute html =~ ~r/value="true"[^>]*>\s*true\s*</
    refute html =~ ~r/value="false"[^>]*>\s*false\s*</
  end

  test "renders binary dropdown with true/false when texts are absent" do
    html =
      render_modal(%{
        name: "BV-1",
        type: :binary_value,
        instance: 1,
        writable: true,
        commandable: false,
        present_value: false,
        present_value_formatted: "false"
      })

    assert html =~ ~s(id="modal-write-value")
    assert html =~ ~s(<select)
    assert html =~ ~r/value="true"[^>]*>\s*true\s*</
    assert html =~ ~r/value="false"[^>]*>\s*false\s*</
  end
end
