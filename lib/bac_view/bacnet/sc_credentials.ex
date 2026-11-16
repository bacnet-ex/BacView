defmodule BacView.BACnet.SCCredentials do
  @moduledoc false

  alias BACnet.Stack.Transport.ScTransport.Credentials

  @max_pem_size 65_536
  @bundle "credentials.json"

  @type summary :: %{expires_at: DateTime.t(), id: String.t()}

  @spec max_pem_size() :: pos_integer()
  def max_pem_size(), do: @max_pem_size

  @spec import_pem(binary(), binary(), [binary()]) :: {:ok, summary()} | {:error, atom()}
  def import_pem(cert, key, issuers) when length(issuers) in 1..2 do
    with true <- Enum.all?([cert, key | issuers], &valid_size?/1),
         {:ok, _credentials} <- validate(cert, key, issuers),
         {:ok, summary} <- summarize(cert, issuers),
         :ok <- save(Jason.encode!(%{cert: cert, key: key, issuers: issuers})) do
      {:ok, summary}
    else
      false -> {:error, :invalid_sc_credentials}
      {:error, _reason} = error -> error
    end
  end

  def import_pem(_cert, _key, _issuers), do: {:error, :invalid_sc_credentials}

  @spec load() :: {:ok, Credentials.t(), String.t()} | {:error, atom()}
  def load() do
    with {:ok, %{"cert" => cert, "key" => key, "issuers" => issuers}} <- read_bundle(),
         {:ok, credentials} <- validate(cert, key, issuers) do
      {:ok, credentials, credential_id(cert, issuers)}
    end
  end

  @spec summary() :: {:ok, summary()} | {:error, atom()}
  def summary() do
    with {:ok, %{"cert" => cert, "issuers" => issuers}} <- read_bundle() do
      summarize(cert, issuers)
    end
  end

  defp read_bundle() do
    with {:ok, contents} <- File.read(Path.join(directory(), @bundle)),
         {:ok, %{"cert" => cert, "key" => key, "issuers" => issuers} = bundle} <-
           Jason.decode(contents),
         true <- is_list(issuers) and length(issuers) in 1..2,
         true <- Enum.all?([cert, key | issuers], &valid_size?/1) do
      {:ok, bundle}
    else
      {:error, :enoent} -> {:error, :missing_sc_credentials}
      _reason -> {:error, :invalid_sc_credentials}
    end
  end

  defp validate(cert, key, issuers) do
    case Credentials.from_pem(cert, key, issuers) do
      {:ok, credentials} -> {:ok, credentials}
      {:error, _reason} -> {:error, :invalid_sc_credentials}
    end
  rescue
    _error -> {:error, :invalid_sc_credentials}
  end

  defp summarize(cert, issuers) do
    case Credentials.certificate(cert) do
      {:ok, certificate} ->
        {:Validity, _not_before, not_after} = X509.Certificate.validity(certificate)
        expires_at = X509.DateTime.to_datetime(not_after)
        {:ok, %{expires_at: expires_at, id: credential_id(cert, issuers)}}

      {:error, _reason} ->
        {:error, :invalid_sc_credentials}
    end
  rescue
    _error -> {:error, :invalid_sc_credentials}
  end

  defp credential_id(cert, issuers) do
    digest = :crypto.hash(:sha256, [cert | issuers])
    Base.encode16(digest)
  end

  defp valid_size?(pem),
    do: is_binary(pem) and byte_size(pem) in 1..@max_pem_size and String.valid?(pem)

  defp save(data) do
    directory = directory()
    filename = Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
    temporary = Path.join(directory, filename)

    with :ok <- File.mkdir_p(directory),
         :ok <- restrict(directory, 0o700),
         :ok <- File.write(temporary, "", [:exclusive]) do
      commit(temporary, Path.join(directory, @bundle), data)
    else
      {:error, _reason} -> {:error, :sc_credential_storage_failed}
    end
  end

  defp commit(temporary, destination, data) do
    with :ok <- restrict(temporary, 0o600),
         :ok <- File.write(temporary, data, [:sync]),
         :ok <- File.rename(temporary, destination) do
      :ok
    else
      {:error, _reason} -> {:error, :sc_credential_storage_failed}
    end
  after
    File.rm(temporary)
  end

  defp restrict(path, mode) do
    case :os.type() do
      {:win32, _family} -> :ok
      _family -> File.chmod(path, mode)
    end
  end

  defp directory() do
    Application.get_env(:bacview, :sc_credentials_directory) ||
      Path.join(:filename.basedir(:user_config, "bacview"), "secure-connect")
  end
end
