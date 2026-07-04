defmodule BacView.BACnet.FileTransferTest do
  use ExUnit.Case, async: true

  alias BacView.BACnet.FileTransfer

  describe "printable_text?/1" do
    test "accepts empty and plain text" do
      assert FileTransfer.printable_text?("")
      assert FileTransfer.printable_text?("Hello BACnet\nline two\t tab")
      assert FileTransfer.printable_text?("Konfiguration: Gerät 42")
    end

    test "rejects binary and invalid utf-8" do
      refute FileTransfer.printable_text?(<<0, 1, 2, 3>>)
      refute FileTransfer.printable_text?("hello" <> <<0>>)
      refute FileTransfer.printable_text?(<<255, 254, 253>>)
    end
  end

  describe "content_view/1" do
    test "returns preview for printable text" do
      data = "line one\nline two"

      assert %{
               printable: true,
               preview: ^data,
               truncated: false,
               size: 17
             } = FileTransfer.content_view(data)
    end

    test "truncates large printable previews" do
      data = String.duplicate("a", 70_000)

      assert %{
               printable: true,
               preview: preview,
               truncated: true,
               size: 70_000
             } = FileTransfer.content_view(data)

      assert byte_size(preview) == 65_536
    end

    test "omits preview for binary data" do
      data = <<0, 1, 2, 3, 4>>

      assert %{
               printable: false,
               preview: nil,
               truncated: false,
               size: 5
             } = FileTransfer.content_view(data)
    end
  end

  describe "download_filename/3" do
    test "uses txt extension for printable files" do
      assert FileTransfer.download_filename(:file, 7, true) == "bacview-file-7.txt"
      assert FileTransfer.download_filename(:file, 7, false) == "bacview-file-7.bin"
    end
  end
end
