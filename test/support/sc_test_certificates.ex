defmodule BacView.Test.SCTestCertificates do
  @moduledoc false

  def issuer() do
    key = X509.PrivateKey.new_ec(:secp256r1)
    cert = X509.Certificate.self_signed(key, "/CN=BacView Integration CA", template: :root_ca)
    {cert, key}
  end

  def pem({issuer, issuer_key}, name) do
    key = X509.PrivateKey.new_ec(:secp256r1)

    cert =
      X509.Certificate.new(X509.PublicKey.derive(key), "/CN=#{name}", issuer, issuer_key,
        template: :server
      )

    {X509.Certificate.to_pem(cert), X509.PrivateKey.to_pem(key),
     [X509.Certificate.to_pem(issuer)]}
  end
end
