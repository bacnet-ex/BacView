defmodule BacView.BACnet.SCCredentialsTest do
  use ExUnit.Case, async: false

  alias BacView.BACnet.SCCredentials
  alias BacView.Test.SCTestCertificates

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    directory = Path.join(tmp_dir, "credentials")
    previous = Application.fetch_env(:bacview, :sc_credentials_directory)
    Application.put_env(:bacview, :sc_credentials_directory, directory)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:bacview, :sc_credentials_directory, value)
        :error -> Application.delete_env(:bacview, :sc_credentials_directory)
      end
    end)

    %{directory: directory}
  end

  test "validates the complete PEM set before replacing the bundle", %{directory: directory} do
    ca = SCTestCertificates.issuer()
    {cert, key, issuers} = SCTestCertificates.pem(ca, "First node")
    {next_cert, next_key, _issuers} = SCTestCertificates.pem(ca, "Replacement node")

    assert {:error, :missing_sc_credentials} = SCCredentials.load()
    assert {:ok, first} = SCCredentials.import_pem(cert, key, issuers)
    assert %DateTime{} = first.expires_at

    assert {:error, :invalid_sc_credentials} =
             SCCredentials.import_pem(next_cert, key, issuers)

    assert {:error, :invalid_sc_credentials} =
             SCCredentials.import_pem(cert, "invalid key", issuers)

    assert {:ok, ^first} = SCCredentials.summary()
    assert {:ok, _credentials, id} = SCCredentials.load()
    assert id == first.id

    assert {:ok, replacement} = SCCredentials.import_pem(next_cert, next_key, issuers)
    assert replacement.id != first.id
    assert {:ok, ^replacement} = SCCredentials.summary()
    assert File.ls!(directory) == ["credentials.json"]

    if match?({:unix, _family}, :os.type()) do
      assert Bitwise.band(File.stat!(directory).mode, 0o777) == 0o700

      path = Path.join(directory, "credentials.json")
      assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o600
    end
  end
end
