defmodule BacView.SettingsTest do
  use ExUnit.Case, async: false

  alias BacView.Settings

  setup do
    on_exit(fn ->
      path = Application.get_env(:bacview, :runtime_settings_path)
      if path, do: File.rm(path)
    end)

    :ok
  end

  test "defaults include stack transport fields" do
    defaults = Settings.defaults()

    assert defaults.transport == "ipv4"
    assert defaults.device_id == 4_194_302
    assert defaults.mstp_baud_rate == :auto
  end

  test "update persists and reloads settings" do
    assert {:ok, settings} =
             Settings.update(
               transport: "ipv4",
               device_id: 4_194_301,
               cov_lifetime_seconds: 120,
               cov_confirmed: true
             )

    assert settings.device_id == 4_194_301
    assert settings.cov_lifetime_seconds == 120
    assert settings.cov_confirmed

    assert Settings.get().device_id == 4_194_301
  end

  test "rejects invalid transport" do
    assert {:error, :invalid_transport} = Settings.update(transport: "bacnet_sc")
  end

  test "accepts mstp baud rate auto" do
    assert {:ok, settings} = Settings.update(mstp_baud_rate: :auto)
    assert settings.mstp_baud_rate == :auto
  end

  test "stack_restart_required? detects transport changes" do
    before = Settings.defaults()
    after_map = %{before | transport: "mstp"}

    assert Settings.stack_restart_required?(before, after_map)
    refute Settings.stack_restart_required?(before, %{before | cov_lifetime_seconds: 60})
  end
end
