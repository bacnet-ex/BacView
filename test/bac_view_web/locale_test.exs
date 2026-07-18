defmodule BacViewWeb.LocaleTest do
  use ExUnit.Case, async: true

  use Gettext, backend: BacViewWeb.Gettext

  setup do
    on_exit(fn -> Gettext.put_locale(BacViewWeb.Gettext, "de") end)
    :ok
  end

  test "German locale shows German strings for German msgids" do
    Gettext.put_locale(BacViewWeb.Gettext, "de")

    assert gettext("Alle Objekte anzeigen") == "Alle Objekte anzeigen"
    assert gettext("Hierarchie") == "Hierarchie"
  end

  test "English locale translates German msgids" do
    Gettext.put_locale(BacViewWeb.Gettext, "en")

    assert gettext("Alle Objekte anzeigen") == "Show all objects"
    assert gettext("Hierarchie") == "Hierarchy"
  end

  test "English locale translates status flags and BBMD labels" do
    Gettext.put_locale(BacViewWeb.Gettext, "en")

    # These were previously missing from en.po because the translation
    # collector only matched t(..., locale_version, ...) and not t(..., lv, ...).
    assert gettext("In Alarm") == "In alarm"
    assert gettext("Übersteuert") == "Overridden"
    assert gettext("Ausser Betrieb") == "Out of service"
    assert gettext("aktiv") == "active"
    assert gettext("inaktiv") == "inactive"
    assert gettext("Registriert") == "Registered"
    assert gettext("Warte auf BBMD") == "Waiting for BBMD"
    assert gettext("Initialisiere") == "Initializing"
    assert gettext("Inaktiv") == "Inactive"
  end

  test "English locale translates multi-line gt flash messages" do
    Gettext.put_locale(BacViewWeb.Gettext, "en")

    assert gettext("Geschriebener Wert weicht vom gelesenen Wert ab: %{value}", value: "1.0") ==
             "Written value differs from the read value: 1.0"

    assert gettext(
             "Geschriebener Wert weicht vom gelesenen Present Value ab: %{value}",
             value: "2.0"
           ) == "Written value differs from the read present value: 2.0"

    assert gettext(
             "Wochenplan-Einträge erlauben nur primitive BACnet-Werte (z. B. REAL, BOOLEAN, ENUMERATED)."
           ) ==
             "Weekly schedule entries only allow primitive BACnet values (e.g. REAL, BOOLEAN, ENUMERATED)."
  end

  test "English catalog covers every msgid collected from the codebase" do
    # Keep in sync with priv/gettext/build_en_translations.py collect_msgids/0.
    # Fails if a new t/gt/gettext call was added without an EN translation entry.
    script = Path.expand("priv/gettext/build_en_translations.py")

    {json, 0} =
      System.cmd(
        "python3",
        [
          "-c",
          """
          import json, runpy, sys
          ns = runpy.run_path(sys.argv[1])
          msgids = ns["collect_msgids"]()
          translations = ns["TRANSLATIONS"]
          missing = [m for m in msgids if m not in translations]
          print(json.dumps({"count": len(msgids), "missing": missing}))
          """,
          script
        ],
        stderr_to_stdout: true
      )

    payload = Jason.decode!(json)
    assert payload["missing"] == [], "Missing EN translations for: #{inspect(payload["missing"])}"
    assert payload["count"] > 500

    Gettext.put_locale(BacViewWeb.Gettext, "en")

    # Spot-check that catalog entries actually resolve (not just map presence)
    assert gettext("Keine Netzwerkschnittstellen gefunden.") == "No network interfaces found."
    assert gettext("Stream-Zugriff") == "Stream access"
    assert gettext("Gerätedienst") == "Device service"
  end

  test "GettextLC.translate! respects explicit locale" do
    assert BacViewWeb.GettextLC.translate!("Netzwerk", %{}, "en", 1) == "Network"
    assert BacViewWeb.GettextLC.translate!("Netzwerk", %{}, "de", 0) == "Netzwerk"
  end
end
