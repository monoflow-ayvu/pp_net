defmodule PPNetTest do
  use ExUnit.Case, async: true

  alias PPNet.Message.Hello
  alias PPNet.Message.SingleCounter
  alias PPNet.Message.Ping
  alias PPNet.Message.Event
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
        0x01
      >>

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
                   data: %{
                     body: <<148, 160, 0>>,
                     payload: <<1, 218, 18, 12, 79, 148, 160, 0>>,
                     type: 1
                   },
                   message: "Failed to parse message of type 1",
                   reason: %Msgpax.UnpackError{reason: :incomplete, __exception__: true}
                 },
                 %PPNet.ParseError{
                   data: %{payload: <<1, 218, 18, 12, 79, 148, 160, 0>>},
                   message: "Failed to parse message for unknown type",
                   reason: :unknown_type
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
               0x01
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
                   data: %{
                     body: <<148, 160, 0>>,
                     payload: <<2, 24, 15, 4, 69, 148, 160, 0>>,
                     type: 2
                   },
                   message: "Failed to parse message of type 2",
                   reason: %Msgpax.UnpackError{reason: :incomplete, __exception__: true}
                 },
                 %PPNet.ParseError{
                   data: %{type: 4, body: "", payload: <<4, 69, 148, 160, 0>>},
                   message: "Failed to parse message of type 4",
                   reason: %Msgpax.UnpackError{reason: :incomplete, __exception__: true}
                 },
                 %PPNet.ParseError{
                   data: %{payload: <<2, 24, 15, 4, 69, 148, 160, 0>>},
                   message: "Failed to parse message for unknown type",
                   reason: :unknown_type
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
               0xDC
             >>
    end
  end

  describe "decode PPNet.Message.Ping" do
    test "parse/1 with valid binary data" do
      payload = <<
        # message type
        0x3,
        0x1D,
        0x67,
        0x4,
        # checksum (adler32)
        0x10,
        # body (msgpack)
        0x93,
        0xCB,
        0x40,
        0x39,
        0x0,
        0x0,
        0x0,
        0x0,
        0x0,
        0x0,
        0xCD,
        0x3,
        0xE8,
        0x80
      >>

      assert %{
               messages: [
                 %Ping{
                   temperature: 25.0,
                   uptime_ms: 1000,
                   extra: %{},
                   checksum: 493_290_512,
                   valid: true
                 }
               ],
               errors: []
             } = PPNet.parse(payload)
    end

    test "parse/1 with valid binary data and extra is present" do
      payload =
        <<0x3, 0x9F, 0xAA, 0xB, 0x91, 0x93, 0xCB, 0x40, 0x39, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0xCD,
          0x3, 0xE8, 0x82, 0xA3, 0x66, 0x6F, 0x6F, 0xA3, 0x62, 0x61, 0x7A, 0xA3, 0x62, 0x61, 0x7A,
          0xA3, 0x62, 0x61, 0x72>>

      assert %{
               messages: [
                 %Ping{
                   valid: true,
                   checksum: 2_678_721_425,
                   extra: %{"baz" => "bar", "foo" => "baz"},
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
               0x1D,
               0x67,
               0x04,
               0x10,
               # body (msgpack)
               0x93,
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
               0x80
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
                 0x6F, 0x6F, 0xA3, 0x62, 0x61, 0x72>>
    end
  end

  describe "decode PPNet.Message.Event" do
    test "parse/1 with valid binary data" do
      payload =
        <<0x4, 0x1, 0xAB, 0xE, 0x68, 0x92, 0xAC, 0x73, 0x65, 0x6E, 0x73, 0x6F, 0x72, 0x5F, 0x61,
          0x6C, 0x65, 0x72, 0x74, 0x82, 0xA5, 0x76, 0x61, 0x6C, 0x75, 0x65, 0x64, 0xA9, 0x73,
          0x65, 0x6E, 0x73, 0x6F, 0x72, 0x5F, 0x69, 0x64, 0x1>>

      assert %{
               messages: [
                 %PPNet.Message.Event{
                   checksum: 27_987_560,
                   data: %{"sensor_id" => 1, "value" => 100},
                   kind: "sensor_alert",
                   valid: true
                 }
               ],
               errors: []
             } = PPNet.parse(payload)
    end
  end

  describe "encode PPNet.Message.Event" do
    test "encode/1 with valid data" do
      message =
        %Event{
          kind: "sensor_alert",
          data: %{sensor_id: 1, value: 100}
        }
        |> PPNet.encode_message()

      assert message ==
               <<0x4, 0xFE, 0xA, 0xE, 0x68, 0x92, 0xAC, 0x73, 0x65, 0x6E, 0x73, 0x6F, 0x72, 0x5F,
                 0x61, 0x6C, 0x65, 0x72, 0x74, 0x82, 0xA9, 0x73, 0x65, 0x6E, 0x73, 0x6F, 0x72,
                 0x5F, 0x69, 0x64, 0x1, 0xA5, 0x76, 0x61, 0x6C, 0x75, 0x65, 0x64>>
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
             } = PPNet.parse(header)

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
                   reason: %Msgpax.UnpackError{__exception__: true, reason: :incomplete}
                 },
                 %PPNet.ParseError{
                   data: %{payload: <<0, 24, 15, 4, 69, 148, 160, 0>>},
                   message: "Failed to parse message for unknown type",
                   reason: :unknown_type
                 }
               ]
             } =
               PPNet.parse(payload)
    end

    test "decode multiple messages" do
      hello =
        PPNet.encode_message(%Hello{
          board_identifier: "Tester",
          board_version: 17_185,
          boot_id: 87_372_886,
          ppnet_version: 1,
          unique_id: "TestRunner",
          version: 4660
        })

      single_counter =
        PPNet.encode_message(%SingleCounter{
          duration_ms: 1500,
          kind: "bar",
          pulses: 0,
          value: 42
        })

      ping =
        PPNet.encode_message(%Ping{
          temperature: 25.0,
          uptime_ms: 1000
        })

      event =
        PPNet.encode_message(%Event{
          kind: :sensor_alert,
          data: %{"sensor_id" => 1, "value" => 100}
        })

      image = File.read!("test/support/static/image.webp")
      [image_header | image_chunks] = PPNet.encode_image(image)

      wrong_message =
        <<0x04, 0xFE, 0xA, 0xE, 0x68, 0x92, 0xAC, 0x73, 0x65, 0x6E, 0x73, 0x6F, 0x72, 0x5F>>

      messages =
        Enum.join(
          [image_header, ping] ++ image_chunks ++ [wrong_message, single_counter, hello, event]
        )

      assert %{
               messages: [
                 %PPNet.Message.ImageHeader{
                   valid: true,
                   checksum: _checksum_image_header,
                   total_chunks: 1,
                   transaction_id: transaction_id
                 },
                 %PPNet.Message.Ping{
                   valid: true,
                   checksum: 493_290_512,
                   extra: %{},
                   uptime_ms: 1000,
                   temperature: 25.0
                 },
                 %PPNet.Message.ImageBody{
                   valid: true,
                   checksum: _image_body_checksum,
                   chunk_data: _chunk_data,
                   chunk_size: 27136,
                   chunk_index: 0,
                   transaction_id: transaction_id
                 },
                 %PPNet.Message.SingleCounter{
                   valid: true,
                   checksum: 403_637_317,
                   duration_ms: 1500,
                   pulses: 0,
                   value: 42,
                   kind: "bar"
                 },
                 %PPNet.Message.Hello{
                   valid: true,
                   checksum: 3_658_615_887,
                   ppnet_version: 1,
                   boot_id: 87_372_886,
                   board_version: 17185,
                   version: 4660,
                   board_identifier: "Tester",
                   unique_id: "TestRunner"
                 },
                 %PPNet.Message.Event{
                   valid: true,
                   checksum: 27_987_560,
                   data: %{"sensor_id" => 1, "value" => 100},
                   kind: "sensor_alert"
                 }
               ],
               errors: [
                 %PPNet.ParseError{
                   message: "Failed to parse message of type 4",
                   reason: %PPNet.ParseError{
                     message: "The message body does not match the expected format",
                     reason: :unknown_format,
                     data:
                       {:unpacked_body,
                        [
                          <<115, 101, 110, 115, 111, 114, 95, 2, 24, 15, 4, 69>>,
                          ["bar", 42, 0, 1500]
                        ]}
                   },
                   data: %{
                     type: 4,
                     body: _body,
                     payload: _payload
                   }
                 },
                 %PPNet.ParseError{
                   message: "Failed to parse message for unknown type",
                   reason: :unknown_type,
                   data: %{
                     payload: <<4, 254, 14, 104, 146, 172, 115, 101, 110, 115, 111, 114, 95>>
                   }
                 }
               ]
             } = PPNet.parse(messages)
    end
  end
end
