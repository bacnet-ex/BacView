defmodule BacViewWeb.ReadPropertyModalLiveTest do
  use BacViewWeb.ConnCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  defmodule FakeClient do
    def read_property(_destination, _object, _property, _opts), do: {:ok, 18.0}
  end

  setup do
    previous_client = Application.get_env(:bacview, :single_property_read_client)
    previous_probe = Application.get_env(:bacview, :device_iam_broadcast_probe)

    Application.put_env(:bacview, :single_property_read_client, FakeClient)
    Application.put_env(:bacview, :device_iam_broadcast_probe, fn _id -> {:error, :no_iam} end)

    on_exit(fn ->
      restore_env(:single_property_read_client, previous_client)
      restore_env(:device_iam_broadcast_probe, previous_probe)
    end)

    :ok
  end

  test "opens the ReadProperty modal from the dashboard topbar", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    refute has_element?(view, "#read-property-modal")

    view
    |> element("#open-read-property-btn")
    |> render_click()

    assert has_element?(view, "#read-property-modal")
    assert has_element?(view, "#read-property-form")
  end

  test "Escape closes the ReadProperty modal", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#open-read-property-btn")
    |> render_click()

    assert has_element?(view, "#read-property-modal")

    render_click(view, "global_keydown", %{
      "key" => "Escape",
      "code" => "Escape",
      "shift" => false
    })

    refute has_element?(view, "#read-property-modal")
  end

  test "typing an incomplete BACnet URI does not crash the modal", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#open-read-property-btn")
    |> render_click()

    html =
      view
      |> form("#read-property-form", %{"read_property" => %{"uri" => "bacnet:"}})
      |> render_change()

    assert has_element?(view, "#read-property-modal")
    refute html =~ "Ungültige BACnet-URI"
    refute has_element?(view, "#read-property-uri-error")
  end

  test "keeps both slashes after bacnet:// when a host character is typed", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#open-read-property-btn")
    |> render_click()

    view
    |> form("#read-property-form", %{"read_property" => %{"uri" => "bacnet://42"}})
    |> render_change()

    assert has_element?(
             view,
             "#read-property-form input[name='read_property[uri]'][value='bacnet://42']"
           )
  end

  test "pasting a BACnet URI fills device and object fields", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#open-read-property-btn")
    |> render_click()

    assert has_element?(view, "#read-property-uri-hint")

    view
    |> form("#read-property-form", %{
      "read_property" => %{"uri" => "bacnet://42/analog-value,5/present-value"}
    })
    |> render_change()

    assert has_element?(
             view,
             "#read-property-form input[name='read_property[device_id]'][value='42']"
           )

    assert has_element?(
             view,
             "#read-property-form input[name='read_property[object_type]'][value='analog-value']"
           )

    assert has_element?(
             view,
             "#read-property-form input[name='read_property[instance]'][value='5']"
           )

    assert has_element?(view, "#read-property-locator-device-id:checked")
  end

  test "editing fields after a URI paste keeps the change and updates the URI", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#open-read-property-btn")
    |> render_click()

    view
    |> form("#read-property-form", %{
      "read_property" => %{"uri" => "bacnet://42/analog-value,5/present-value"}
    })
    |> render_change()

    view
    |> form("#read-property-form", %{
      "read_property" => %{"property" => "object-name", "instance" => "9"}
    })
    |> render_change()

    assert has_element?(
             view,
             "#read-property-form input[name='read_property[property]'][value='object-name']"
           )

    assert has_element?(
             view,
             "#read-property-form input[name='read_property[instance]'][value='9']"
           )

    assert has_element?(
             view,
             "#read-property-form input[name='read_property[uri]'][value='bacnet://42/analog-value,9/object-name']"
           )
  end

  test "switching to address after a URI paste keeps the address locator", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#open-read-property-btn")
    |> render_click()

    view
    |> form("#read-property-form", %{
      "read_property" => %{"uri" => "bacnet://42/analog-value,5/present-value"}
    })
    |> render_change()

    refute has_element?(view, "#read-property-address-uri-hint")

    view
    |> form("#read-property-form", %{
      "read_property" => %{"locator" => "address", "address" => "10.0.0.1"}
    })
    |> render_change()

    assert has_element?(view, "#read-property-locator-address:checked")
    assert has_element?(view, "#read-property-address-uri-hint")

    assert has_element?(
             view,
             "#read-property-form input[name='read_property[object_type]'][value='analog-value']"
           )

    assert has_element?(
             view,
             "#read-property-form input[name='read_property[instance]'][value='5']"
           )
  end

  test "submit after a URI paste uses the address locator and edited fields", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#open-read-property-btn")
    |> render_click()

    view
    |> form("#read-property-form", %{
      "read_property" => %{"uri" => "bacnet://42/analog-value,5/present-value"}
    })
    |> render_change()

    view
    |> form("#read-property-form", %{
      "read_property" => %{
        "locator" => "address",
        "address" => "10.0.0.1",
        "property" => "object-name"
      }
    })
    |> render_submit()

    render_async(view)
    assert has_element?(view, "#read-property-result")
    result = render(element(view, "#read-property-result"))
    assert result =~ "10.0.0.1:47808"
    assert result =~ "object-name"
    refute result =~ "present-value"
  end

  test "pasting a URI while address is selected keeps the address locator", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#open-read-property-btn")
    |> render_click()

    view
    |> form("#read-property-form", %{"read_property" => %{"locator" => "address"}})
    |> render_change()

    view
    |> form("#read-property-form", %{
      "read_property" => %{"uri" => "bacnet://42/analog-value,5/present-value"}
    })
    |> render_change()

    assert has_element?(view, "#read-property-locator-address:checked")

    assert has_element?(
             view,
             "#read-property-form input[name='read_property[device_id]'][value='42']"
           )
  end

  test "pasting .this without a current device shows an error and still fills the object", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#open-read-property-btn")
    |> render_click()

    view
    |> form("#read-property-form", %{
      "read_property" => %{"uri" => "bacnet://.this/analog-value,1"}
    })
    |> render_change()

    assert has_element?(view, "#read-property-uri-error")

    assert has_element?(
             view,
             "#read-property-form input[name='read_property[object_type]'][value='analog-value']"
           )

    assert has_element?(
             view,
             "#read-property-form input[name='read_property[instance]'][value='1']"
           )
  end

  test "submit without a locator shows an error", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#open-read-property-btn")
    |> render_click()

    view
    |> form("#read-property-form", %{
      "read_property" => %{
        "locator" => "device_id",
        "device_id" => "",
        "object_type" => "analog-value",
        "instance" => "1"
      }
    })
    |> render_submit()

    html = render_async(view)
    assert html =~ "Bitte eine Geräte-ID angeben" or html =~ "Eigenschaft lesen fehlgeschlagen"
    assert has_element?(view, "#read-property-error")
  end

  test "reads a property by IPv4 address", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#open-read-property-btn")
    |> render_click()

    view
    |> form("#read-property-form", %{
      "read_property" => %{
        "locator" => "address",
        "address" => "10.0.0.1",
        "object_type" => "analog-value",
        "instance" => "1",
        "property" => "present-value"
      }
    })
    |> render_submit()

    html = render_async(view)
    assert has_element?(view, "#read-property-result")
    assert has_element?(view, "#read-property-result-value")
    assert html =~ "10.0.0.1:47808"
    assert html =~ "bac-read-property-result-value"
  end

  defp restore_env(key, nil), do: Application.delete_env(:bacview, key)
  defp restore_env(key, value), do: Application.put_env(:bacview, key, value)
end
