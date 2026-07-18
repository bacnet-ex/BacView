defmodule BacViewWeb.StatusFlagsIconsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BACnet.Protocol.StatusFlags
  alias BacViewWeb.StatusFlagsIcons

  test "active_flags returns only set BACnet status flags" do
    flags = %StatusFlags{
      in_alarm: true,
      fault: false,
      overridden: true,
      out_of_service: false
    }

    assert StatusFlagsIcons.active_flags(flags) == [:in_alarm, :overridden]
    assert StatusFlagsIcons.active_flags(nil) == []
  end

  test "mode :stats renders bac-stat flag boxes with large icons" do
    flags = %StatusFlags{
      in_alarm: true,
      fault: false,
      overridden: true,
      out_of_service: false
    }

    html =
      render_component(&StatusFlagsIcons.status_flags_icons/1, %{
        flags: flags,
        mode: :stats,
        locale: "de",
        locale_version: 0
      })

    assert html =~ "bac-stat-flag"
    assert html =~ "bac-stat-label"
    assert html =~ "In Alarm"
    assert html =~ "bac-stat-flag-active"
    assert html =~ StatusFlagsIcons.flag_class(:in_alarm)
    assert html =~ StatusFlagsIcons.flag_class(:overridden)
    refute html =~ StatusFlagsIcons.flag_class(:out_of_service)
  end

  test "flag_class uses distinct active colors for each status flag" do
    assert StatusFlagsIcons.flag_class(:in_alarm) == "text-[var(--bac-orange)]"
    assert StatusFlagsIcons.flag_class(:fault) == "text-[var(--bac-rose)]"
    assert StatusFlagsIcons.flag_class(:overridden) == "text-[var(--bac-violet)]"
    assert StatusFlagsIcons.flag_class(:out_of_service) == "text-[var(--bac-amber)]"

    flags = %StatusFlags{
      in_alarm: false,
      fault: false,
      overridden: false,
      out_of_service: true
    }

    assert StatusFlagsIcons.flag_icon_class(flags, :out_of_service) ==
             StatusFlagsIcons.flag_class(:out_of_service)

    assert StatusFlagsIcons.flag_icon_class(flags, :fault) ==
             "text-[var(--bac-text-faint)] opacity-40"
  end

  test "mode :all renders every status flag icon" do
    flags = %StatusFlags{
      in_alarm: true,
      fault: false,
      overridden: true,
      out_of_service: false
    }

    html =
      render_component(&StatusFlagsIcons.status_flags_icons/1, %{
        flags: flags,
        mode: :all,
        locale: "de",
        locale_version: 0
      })

    assert html =~ "In Alarm (aktiv)"
    assert html =~ "Störung (inaktiv)"
    assert html =~ StatusFlagsIcons.flag_class(:in_alarm)
    assert html =~ StatusFlagsIcons.flag_icon_class(flags, :fault)
  end

  test "mode :stats uses English labels when locale is en" do
    flags = %StatusFlags{
      in_alarm: true,
      fault: false,
      overridden: true,
      out_of_service: false
    }

    html =
      render_component(&StatusFlagsIcons.status_flags_icons/1, %{
        flags: flags,
        mode: :stats,
        locale: "en",
        locale_version: 1
      })

    assert html =~ "In alarm"
    assert html =~ "Fault"
    assert html =~ "Overridden"
    assert html =~ "Out of service"
    refute html =~ "Störung"
    refute html =~ "Übersteuert"
    refute html =~ "Ausser Betrieb"
  end
end
