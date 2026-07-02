defmodule PPNetStreamTest do
  use ExUnit.Case, async: true

  alias PPNet.Message.ChunkedMessageHeader
  alias PPNet.Message.Image
  alias PPNet.Message.SingleCounter

  @image_id "00000000-0000-0000-0000-000000000000"
  @datetime ~U[2026-03-27 20:15:41Z]

  defp image(data) do
    %Image{id: @image_id, data: data, format: :webp, datetime: @datetime}
  end

  describe "encode_message_stream/2" do
    test "single-frame message yields exactly the encode_message/2 binary" do
      message = %SingleCounter{kind: "bar", value: 42, pulses: 0, duration_ms: 1500, datetime: ~U[2026-03-27 12:58:06Z]}

      assert Enum.to_list(PPNet.encode_message_stream(message)) == [PPNet.encode_message(message)]
    end

    test "chunked message parses and reassembles to the original" do
      message = image(File.read!("test/support/static/image.webp"))

      frames =
        message
        |> PPNet.encode_message_stream(limit: 200)
        |> Enum.to_list()

      assert Enum.all?(frames, &(is_binary(&1) and byte_size(&1) <= 200))

      assert %{messages: [%ChunkedMessageHeader{message_module: Image} = header | chunks], errors: []} =
               frames
               |> Enum.join()
               |> PPNet.parse()

      assert header.total_chunks == length(chunks)
      assert {:ok, ^message} = PPNet.chunked_to_message([header | chunks])
    end

    test "the header frame comes first" do
      message = image(File.read!("test/support/static/image.webp"))

      [header_frame] =
        message
        |> PPNet.encode_message_stream()
        |> Enum.take(1)

      assert %{messages: [%ChunkedMessageHeader{message_module: Image}], errors: []} = PPNet.parse(header_frame)
    end
  end

  describe "chunk splitting" do
    # chunk_size for limit 200 is 200 - 22 = 178; Image.pack/1 adds 25 bytes on
    # top of the raw data.
    test "chunk boundaries are byte-identical to the 0.1.5 list-based algorithm" do
      chunk_size = 178
      pack_overhead = 25

      # exact multiple of chunk_size, one byte over, one byte under, arbitrary
      data_sizes = [
        chunk_size * 3 - pack_overhead,
        chunk_size * 3 - pack_overhead + 1,
        chunk_size * 3 - pack_overhead - 1,
        1000
      ]

      for data_size <- data_sizes do
        message = image(:crypto.strong_rand_bytes(data_size))
        packed = Image.pack(message)
        assert byte_size(packed) == data_size + pack_overhead

        reference_chunks =
          packed
          |> :binary.bin_to_list()
          |> Enum.chunk_every(chunk_size)
          |> Enum.map(&IO.iodata_to_binary/1)

        [_header_frame | chunk_frames] = PPNet.encode_message(message, limit: 200)

        assert %{messages: bodies, errors: []} =
                 chunk_frames
                 |> Enum.join()
                 |> PPNet.parse()

        assert Enum.map(bodies, & &1.chunk_data) == reference_chunks
      end
    end

    test "raises when the limit leaves no room for chunk data" do
      # limit 22 is the clamp minimum: the header still fits, but a chunk would
      # carry 0 payload bytes
      message = image(:crypto.strong_rand_bytes(1000))

      assert_raise ArgumentError, ~r/leaves no room for chunk data/, fn ->
        PPNet.encode_message(message, limit: 22)
      end
    end
  end
end
