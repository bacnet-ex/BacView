defmodule BacView.SettingsTest do
  use ExUnit.Case, async: false

  alias BacView.BACnet.Discovery
  alias BacView.Settings

  setup do
    on_exit(fn ->
      path = Application.get_env(:bacview, :runtime_settings_path)
      if path, do: File.rm(path)

      _ = restore_default_settings()
    end)

    assert {:ok, _} = restore_default_settings()
    :ok
  end

  test "defaults include stack transport fields" do
    defaults = Settings.defaults()

    assert defaults.transport == "ipv4"
    assert defaults.ipv4_port == 47_808
    assert defaults.device_id == 4_194_302
    assert defaults.mstp_baud_rate == :auto
    assert defaults.network_number == 0
    assert defaults.max_apdu_length == 1476
    assert defaults.scan_on_online == false
  end

  test "update persists scan_on_online" do
    assert {:ok, settings} = Settings.update(scan_on_online: true)
    assert settings.scan_on_online
    assert Settings.scan_on_online?()

    assert {:ok, settings} = Settings.update(scan_on_online: false)
    refute settings.scan_on_online
    refute Settings.scan_on_online?()
  end

  test "loads legacy auto_scan_on_iam as scan_on_online" do
    path = Application.get_env(:bacview, :runtime_settings_path)
    assert is_binary(path)

    File.mkdir_p!(Path.dirname(path))

    File.write!(
      path,
      Jason.encode!(%{
        "transport" => "ipv4",
        "device_id" => 4_194_302,
        "auto_scan_on_iam" => true
      })
    )

    # Application owns Settings (:permanent); stop triggers a reload from disk.
    :ok = GenServer.stop(Settings)

    Enum.reduce_while(1..50, nil, fn _attempt, _acc ->
      if Process.whereis(Settings) do
        {:halt, :ok}
      else
        Process.sleep(10)
        {:cont, nil}
      end
    end)

    assert Process.whereis(Settings)
    assert Settings.get().scan_on_online
    assert Settings.scan_on_online?()
  end

  test "accepts network_number 0 and rejects 65535" do
    assert {:ok, settings} = Settings.update(network_number: 0)
    assert settings.network_number == 0

    assert {:ok, settings} = Settings.update(network_number: 65_534)
    assert settings.network_number == 65_534

    assert {:error, :invalid_settings} = Settings.update(network_number: 65_535)
    assert {:error, :invalid_settings} = Settings.update(network_number: -1)
  end

  test "accepts max_apdu_length in range" do
    assert {:ok, settings} = Settings.update(max_apdu_length: 480)
    assert settings.max_apdu_length == 480

    assert {:error, :invalid_settings} = Settings.update(max_apdu_length: 49)
    assert {:error, :invalid_settings} = Settings.update(max_apdu_length: 1477)
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
    refute Settings.stack_restart_required?(before, %{before | cov_increment: 0.5})
  end

  test "defaults cov_increment to nil" do
    assert Settings.defaults().cov_increment == nil
  end

  test "update accepts cov_increment and clears it with nil" do
    assert {:ok, settings} = Settings.update(cov_increment: 0.25)
    assert settings.cov_increment == 0.25
    assert Settings.get().cov_increment == 0.25

    assert {:ok, cleared} = Settings.update(cov_increment: nil)
    assert cleared.cov_increment == nil
  end

  test "rejects negative cov_increment" do
    assert {:error, :invalid_settings} = Settings.update(cov_increment: -0.1)
  end

  test "accepts ipv4 port in valid range" do
    assert {:ok, settings} = Settings.update(ipv4_port: 48_000)
    assert settings.ipv4_port == 48_000
  end

  test "rejects ipv4 port below 47808" do
    assert {:error, :invalid_settings} = Settings.update(ipv4_port: 47_807)
  end

  test "rejects ipv4 port above 65535" do
    assert {:error, :invalid_settings} = Settings.update(ipv4_port: 65_536)
  end

  test "stack_restart_required? detects ipv4 port changes" do
    before = Settings.defaults()
    after_map = %{before | ipv4_port: 48_000}

    assert Settings.stack_restart_required?(before, after_map)
  end

  test "discovery scan uses configured ipv4 port for unicast targets" do
    assert {:ok, _} = Settings.update(ipv4_port: 48_123)

    assert {:ok, opts} =
             Discovery.parse_scan_params(%{"timeout_ms" => "1000", "target_ip" => "10.0.0.42"})

    assert Keyword.fetch!(opts, :destination) == [{{10, 0, 0, 42}, 48_123}]
  end

  defp restore_default_settings do
    if Process.whereis(Settings) do
      defaults = Settings.defaults()

      Settings.update(
        transport: defaults.transport,
        ipv4_port: defaults.ipv4_port,
        device_id: defaults.device_id,
        network_number: defaults.network_number,
        max_apdu_length: defaults.max_apdu_length,
        cov_lifetime_seconds: defaults.cov_lifetime_seconds,
        cov_confirmed: defaults.cov_confirmed,
        scan_on_online: defaults.scan_on_online,
        cov_increment: defaults.cov_increment,
        mstp_local_address: defaults.mstp_local_address,
        mstp_baud_rate: defaults.mstp_baud_rate
      )
    else
      {:ok, Settings.defaults()}
    end
  end
end
