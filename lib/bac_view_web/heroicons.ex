defmodule BacViewWeb.Heroicons do
  @moduledoc false

  @root Path.expand("../../deps/heroicons/optimized", __DIR__)

  @variants [
    {"", "24/outline"},
    {"-solid", "24/solid"},
    {"-mini", "20/solid"},
    {"-micro", "16/solid"}
  ]

  @external_resource @root

  @icons (for {suffix, dir} <- @variants,
              variant_path = Path.join(@root, dir),
              File.dir?(variant_path),
              file <- File.ls!(variant_path),
              String.ends_with?(file, ".svg"),
              basename = Path.basename(file, ".svg"),
              name = "hero-" <> basename <> suffix,
              svg = File.read!(Path.join(variant_path, file)),
              into: %{} do
            {name, String.trim(svg)}
          end)

  @spec svg(String.t()) :: String.t() | nil
  def svg("hero-" <> _icons = name), do: Map.get(@icons, name)
  def svg(_icons), do: nil
end
