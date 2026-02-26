defmodule PPNetTest do
  use ExUnit.Case, async: true

  alias PPNet.Message.Hello
  alias PPNet.Message.SingleCounter
  alias PPNet.Message.Ping
  alias PPNet.Message.ImageHeader
  alias PPNet.Message.ImageBody

  describe "decode PPNet.Message.Hello" do
    test "parse/1 with valid binary data" do
      payload = <<
        # message type
        0x01,
        # checksum (adler32)
        0xDA,
        0x12,
        0x0C,
        0x4F,
        # body (msgpack)
        0x96,
        0xAA,
        0x54,
        0x65,
        0x73,
        0x74,
        0x52,
        0x75,
        0x6E,
        0x6E,
        0x65,
        0x72,
        0xA6,
        0x54,
        0x65,
        0x73,
        0x74,
        0x65,
        0x72,
        0xCD,
        0x12,
        0x34,
        0xCD,
        0x43,
        0x21,
        0xCE,
        0x05,
        0x35,
        0x34,
        0x56,
        0x01,
        "\n"
      >>

      assert %{
               messages: [
                 %Hello{
                   valid: false,
                   checksum: 3_658_615_887,
                   ppnet_version: 1,
                   boot_id: 87_372_886,
                   board_version: 17185,
                   version: 4660,
                   board_identifier: "Tester",
                   unique_id: "TestRunner"
                 }
               ],
               errors: []
             } = PPNet.parse(payload)
    end

    test "parse/1 with valid binary data when payload is a" do
      payload =
        :binary.bin_to_list(
          <<0x01, 0xDA, 0x12, 0x0C, 0x4F, 0x96, 0xAA, 0x54, 0x65, 0x73, 0x74, 0x52, 0x75, 0x6E,
            0x6E, 0x65, 0x72, 0xA6, 0x54, 0x65, 0x73, 0x74, 0x65, 0x72, 0xCD, 0x12, 0x34, 0xCD,
            0x43, 0x21, 0xCE, 0x05, 0x35, 0x34, 0x56, 0x01>>
        )

      assert %{
               messages: [
                 %Hello{
                   valid: true,
                   checksum: 3_658_615_887,
                   ppnet_version: 1,
                   boot_id: 87_372_886,
                   board_version: 17185,
                   version: 4660,
                   board_identifier: "Tester",
                   unique_id: "TestRunner"
                 }
               ],
               errors: []
             } = PPNet.parse(payload)
    end

    test "parse/1 with invalid binary data" do
      payload = <<
        # message type
        0x01,
        # checksum (adler32)
        0xDA,
        0x12,
        0x0C,
        0x4F,
        # body (msgpack)
        # Invalid MsgPack for Hello
        0x94,
        0xA0,
        0x00
      >>

      assert %{
               messages: [],
               errors: [
                 %PPNet.ParseError{
                   message: "Failed to parse message of type 1",
                   reason: %Msgpax.UnpackError{reason: :incomplete},
                   data: %{
                     type: 1,
                     body: <<148, 160, 0>>,
                     payload: <<1, 218, 18, 12, 79, 148, 160, 0>>
                   }
                 }
               ]
             } = PPNet.parse(payload)
    end
  end

  describe "encode PPNet.Message.Hello" do
    test "encode/1 with valid data" do
      message = %Hello{
        board_identifier: "Tester",
        board_version: 17_185,
        boot_id: 87_372_886,
        ppnet_version: 1,
        unique_id: "TestRunner",
        version: 4660
      }

      assert PPNet.encode_message(message, :raw) == <<
               # message type
               0x01,
               # checksum (adler32)
               0xDA,
               0x12,
               0x0C,
               0x4F,
               # body (msgpack)
               0x96,
               0xAA,
               0x54,
               0x65,
               0x73,
               0x74,
               0x52,
               0x75,
               0x6E,
               0x6E,
               0x65,
               0x72,
               0xA6,
               0x54,
               0x65,
               0x73,
               0x74,
               0x65,
               0x72,
               0xCD,
               0x12,
               0x34,
               0xCD,
               0x43,
               0x21,
               0xCE,
               0x05,
               0x35,
               0x34,
               0x56,
               0x01,
               "\n"
             >>
    end
  end

  describe "decode PPNet.Message.SingleCounter" do
    test "parse/1 with valid binary data" do
      payload = <<
        # message type
        0x02,
        # checksum (adler32)
        0x18,
        0x0F,
        0x04,
        0x45,
        # body (msgpack)
        0x94,
        0xA3,
        0x62,
        0x61,
        0x72,
        0x2A,
        0x00,
        0xCD,
        0x05,
        0xDC
      >>

      assert %{
               messages: [
                 %SingleCounter{
                   valid: true,
                   checksum: 403_637_317,
                   duration_ms: 1500,
                   pulses: 0,
                   value: 42,
                   kind: "bar"
                 }
               ],
               errors: []
             } =
               PPNet.parse(payload)
    end

    test "parse/1 with valid binary data when payload is a list" do
      payload =
        :binary.bin_to_list(
          <<0x02, 0x18, 0x0F, 0x04, 0x45, 0x94, 0xA3, 0x62, 0x61, 0x72, 0x2A, 0x00, 0xCD, 0x05,
            0xDC>>
        )

      assert PPNet.parse(payload) ==
               %{
                 messages: [
                   %SingleCounter{
                     valid: true,
                     checksum: 403_637_317,
                     duration_ms: 1500,
                     pulses: 0,
                     value: 42,
                     kind: "bar"
                   }
                 ],
                 errors: []
               }
    end

    test "parse/1 with invalid binary data" do
      payload = <<
        # message type
        0x02,
        # checksum (adler32)
        0x18,
        0x0F,
        0x04,
        0x45,
        # body (msgpack)
        # Invalid MsgPack for SingleCounter
        0x94,
        0xA0,
        0x00
      >>

      assert %{
               messages: [],
               errors: [
                 %PPNet.ParseError{
                   message: "Failed to parse message of type 2",
                   reason: %Msgpax.UnpackError{reason: :incomplete},
                   data: %{
                     type: 2,
                     body: <<148, 160, 0>>,
                     payload: <<2, 24, 15, 4, 69, 148, 160, 0>>
                   }
                 }
               ]
             } =
               PPNet.parse(payload)
    end
  end

  describe "encode PPNet.Message.SingleCounter" do
    test "encode/1 with valid data" do
      message = %SingleCounter{
        duration_ms: 1500,
        kind: "bar",
        pulses: 0,
        value: 42
      }

      assert PPNet.encode_message(message, :raw) == <<
               # message type
               0x02,
               # checksum (adler32)
               0x18,
               0x0F,
               0x04,
               0x45,
               # body (msgpack)
               0x94,
               0xA3,
               0x62,
               0x61,
               0x72,
               0x2A,
               0x00,
               0xCD,
               0x05,
               0xDC,
               "\n"
             >>
    end
  end

  describe "decode PPNet.Message.Ping" do
    test "parse/1 with valid binary data" do
      payload = <<
        # message type
        0x03,
        # checksum (adler32)
        0x19,
        0x4A,
        0x03,
        0x8F,
        # body (msgpack)
        0x92,
        0xCB,
        0x40,
        0x39,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0xCD,
        0x03,
        0xE8
      >>

      assert %{
               messages: [
                 %Ping{
                   temperature: 25.0,
                   uptime_ms: 1000,
                   extra: %{},
                   checksum: 424_280_975,
                   valid: true
                 }
               ],
               errors: []
             } = PPNet.parse(payload)
    end

    test "parse/1 with valid binary data and extra is present" do
      payload =
        <<0x03, 0x7E, 0x01, 0x0A, 0x2C, 0x93, 0xCB, 0x40, 0x39, 0x00, 0x00, 0x00, 0x00, 0x00,
          0x00, 0xCD, 0x03, 0xE8, 0x82, 0xA3, 0x62, 0x61, 0x7A, 0x7B, 0xA3, 0x66, 0x6F, 0x6F,
          0xA3, 0x62, 0x61, 0x72>>

      assert %{
               messages: [
                 %Ping{
                   valid: true,
                   checksum: 2_113_997_356,
                   extra: %{},
                   uptime_ms: 1000,
                   temperature: 25.0
                 }
               ],
               errors: []
             } = PPNet.parse(payload)
    end
  end

  describe "encode PPNet.Message.Ping" do
    test "encode/1 with valid data" do
      message = %Ping{
        temperature: 25.0,
        uptime_ms: 1000
      }

      assert PPNet.encode_message(message, :raw) == <<
               # message type
               0x03,
               # checksum (adler32)
               0x19,
               0x4A,
               0x03,
               0x8F,
               # body (msgpack)
               0x92,
               0xCB,
               0x40,
               0x39,
               0x00,
               0x00,
               0x00,
               0x00,
               0x00,
               0x00,
               0xCD,
               0x03,
               0xE8,
               "\n"
             >>
    end

    test "encode/1 with valid data and extra" do
      message = %Ping{
        temperature: 25.0,
        uptime_ms: 1000,
        extra: %{foo: "bar", baz: 123}
      }

      assert PPNet.encode_message(message, :raw) ==
               <<0x03, 0x7E, 0x01, 0x0A, 0x2C, 0x93, 0xCB, 0x40, 0x39, 0x00, 0x00, 0x00, 0x00,
                 0x00, 0x00, 0xCD, 0x03, 0xE8, 0x82, 0xA3, 0x62, 0x61, 0x7A, 0x7B, 0xA3, 0x66,
                 0x6F, 0x6F, 0xA3, 0x62, 0x61, 0x72, "\n">>
    end
  end

  describe "encode image" do
    test "encode/1 with valid data limited to 200 bytes" do
      image = File.read!("test/support/static/image.webp")
      [header | chunks] = PPNet.encode_image(image, 200)

      assert %{
               messages: [
                 %ImageHeader{
                   valid: true,
                   checksum: checksum,
                   total_chunks: 146,
                   transaction_id: transaction_id
                 }
               ],
               errors: []
             } =
               header
               |> String.trim_trailing("\n")
               |> PPNet.parse()

      assert is_integer(checksum)
      assert is_integer(transaction_id)

      assert Enum.all?(chunks, fn chunk ->
               %{
                 messages: [
                   %ImageBody{
                     valid: true,
                     checksum: _checksum,
                     chunk_data: chunk_data,
                     chunk_size: chunk_size,
                     chunk_index: chunk_index,
                     transaction_id: ^transaction_id
                   }
                 ],
                 errors: []
               } =
                 chunk
                 |> PPNet.parse()

               assert is_integer(transaction_id)
               assert is_integer(chunk_index)
               assert is_binary(chunk_data)
               assert byte_size(chunk_data) == chunk_size
               assert byte_size(chunk) <= 200
             end)
    end

    test "encode/1 with valid data without limit" do
      image = File.read!("test/support/static/image.webp")

      messages =
        image
        |> PPNet.encode_image()
        |> Enum.join()

      assert %{
               errors: [],
               messages: [
                 %PPNet.Message.ImageHeader{
                   checksum: _checksum_header,
                   total_chunks: 1,
                   transaction_id: transaction_id,
                   valid: true
                 },
                 %PPNet.Message.ImageBody{
                   checksum: _checksum_body,
                   chunk_size: 27136,
                   valid: true,
                   transaction_id: transaction_id,
                   chunk_data: ^image,
                   chunk_index: 0
                 }
               ]
             } = PPNet.parse(messages)
    end
  end

  describe "decode image" do
    test "parse/1 with valid binary data" do
      payload = File.read!("test/support/static/image.webp")

      assert %{
               messages: [
                 %PPNet.Message.ImageHeader{
                   valid: true,
                   checksum: _checksum,
                   total_chunks: 146,
                   transaction_id: transaction_id
                 }
                 | chunks
               ],
               errors: []
             } =
               payload
               |> PPNet.encode_image(200)
               |> Enum.join()
               |> PPNet.parse()

      assert Enum.all?(chunks, fn chunk ->
               %ImageBody{
                 valid: true,
                 checksum: _checksum,
                 chunk_data: chunk_data,
                 chunk_size: chunk_size,
                 chunk_index: chunk_index,
                 transaction_id: ^transaction_id
               } = chunk

               assert is_integer(transaction_id)
               assert is_integer(chunk_index)
               assert is_binary(chunk_data)
               assert byte_size(chunk_data) == chunk_size
             end)
    end
  end

  describe "PPNet" do
    test "unknown message type" do
      payload = <<
        # message type
        0x00,
        # checksum (adler32)
        0x18,
        0x0F,
        0x04,
        0x45,
        # body (msgpack)
        0x94,
        0xA0,
        0x00
      >>

      assert %{
               messages: [],
               errors: [
                 %PPNet.ParseError{
                   data: %{body: "", payload: <<4, 69, 148, 160, 0>>, type: 4},
                   message: "Failed to parse message of type 4",
                   reason: %Msgpax.UnpackError{reason: :incomplete, __exception__: true}
                 },
                 %PPNet.ParseError{
                   data: %{payload: <<0, 24, 15>>},
                   message: "Failed to parse message for unknown type",
                   reason: :unknown_type
                 }
               ]
             } =
               PPNet.parse(payload)
    end
  end
end
