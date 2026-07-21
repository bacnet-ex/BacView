defmodule BacView.BuildInfoTest do
  use ExUnit.Case, async: true

  alias BacView.BuildInfo

  test "version/0 returns a non-empty version string" do
    version = BuildInfo.version()
    assert is_binary(version)
    assert version != ""
    assert version =~ ~r/^\d+\.\d+\.\d+/
  end

  test "version_label/0 includes version and optional git suffix" do
    label = BuildInfo.version_label()
    assert String.starts_with?(label, BuildInfo.version())

    case BuildInfo.git_suffix() do
      "" ->
        assert label == BuildInfo.version()

      "+" <> sha ->
        assert label == BuildInfo.version() <> "+" <> sha
        assert sha =~ ~r/^[0-9a-f]+$/i
    end
  end

  test "built_at/0 returns an ISO-8601 timestamp" do
    built_at = BuildInfo.built_at()
    assert is_binary(built_at)
    assert {:ok, %DateTime{}, _offset} = DateTime.from_iso8601(built_at)
  end
end
