defmodule PPNetTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias PPNet.Message.ChunckedMessageBody
  alias PPNet.Message.ChunckedMessageHeader
  alias PPNet.Message.Event
  alias PPNet.Message.Hello
  alias PPNet.Message.Image
  alias PPNet.Message.Ping
  alias PPNet.Message.SingleCounter

  require Logger

  describe "decode PPNet.Message.Hello" do
    test "parse/1 with valid binary data" do
      payload =
        <<0x29, 0x01, 0x96, 0xAA, 0x54, 0x65, 0x73, 0x74, 0x52, 0x75, 0x6E, 0x6E, 0x65, 0x72, 0xA6, 0x54, 0x65, 0x73,
          0x74, 0x65, 0x72, 0xCD, 0x12, 0x34, 0xCD, 0x43, 0x21, 0xCE, 0x05, 0x35, 0x34, 0x56, 0x01, 0x8F, 0xA5, 0x77,
          0xCC, 0xD7, 0x9B, 0x4C, 0xF4, 0x00>>

      assert %{
               messages: [
                 %Hello{
                   ppnet_version: 1,
                   boot_id: 87_372_886,
                   board_version: 17_185,
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
          <<0x29, 0x01, 0x96, 0xAA, 0x54, 0x65, 0x73, 0x74, 0x52, 0x75, 0x6E, 0x6E, 0x65, 0x72, 0xA6, 0x54, 0x65, 0x73,
            0x74, 0x65, 0x72, 0xCD, 0x12, 0x34, 0xCD, 0x43, 0x21, 0xCE, 0x05, 0x35, 0x34, 0x56, 0x01, 0x8F, 0xA5, 0x77,
            0xCC, 0xD7, 0x9B, 0x4C, 0xF4, 0x00>>
        )

      assert %{
               messages: [
                 %Hello{
                   ppnet_version: 1,
                   boot_id: 87_372_886,
                   board_version: 17_185,
                   version: 4660,
                   board_identifier: "Tester",
                   unique_id: "TestRunner"
                 }
               ],
               errors: []
             } = PPNet.parse(payload)
    end

    test "parse/1 with valid binary data when payload is corrupted" do
      payload =
        <<0x29, 0x01, 0x96, 0xAA, 0x54, 0x65, 0x73, 0x74, 0x52, 0x75, 0x6E, 0x6E, 0x65, 0x72, 0xA6, 0x54, 0x65, 0x73,
          0x74, 0x65, 0x72, 0xCD, 0x12, 0x34, 0xCD, 0x43, 0x21, 0xCE, 0x05, 0x35, 0x34, 0x56, 0x01, 0x8F, 0xA5, 0x77,
          0xCC, 0xD7, 0x9B, 0x4C, 0xF4, 0x00>>

      <<a::binary-size(3)-unit(8), _b::binary-size(1)-unit(8), rest::binary>> = payload
      corrupted = <<a::binary-size(3)-unit(8), 1::unsigned-integer-size(1)-unit(8), rest::binary>>
      {result, log} = with_log(fn -> PPNet.parse(corrupted) end)

      assert result == %{
               messages: [
                 %Hello{
                   version: 4660,
                   ppnet_version: 1,
                   boot_id: 87_372_886,
                   board_version: 17_185,
                   board_identifier: "Tester",
                   unique_id: "TestRunner"
                 }
               ],
               errors: []
             }

      assert log =~ "Reed-Solomon corrected 1 errors in message of type #{Hello}"
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
                   data: %{payload: <<1, 218, 18, 12, 79, 148, 160>>},
                   message: "Failed to parse message",
                   reason: {:cobs, "Offset byte specifies more bytes than available"}
                 }
               ]
             } = PPNet.parse(payload)
    end
  end

  describe "encode PPNet.Message.Hello" do
    test "encode/1 with valid data" do
      message =
        %Hello{
          board_identifier: "Tester",
          board_version: 17_185,
          boot_id: 87_372_886,
          ppnet_version: 1,
          unique_id: "TestRunner",
          version: 4660
        }

      assert PPNet.encode_message(message) ==
               <<0x29, 0x01, 0x96, 0xAA, 0x54, 0x65, 0x73, 0x74, 0x52, 0x75, 0x6E, 0x6E, 0x65, 0x72, 0xA6, 0x54, 0x65,
                 0x73, 0x74, 0x65, 0x72, 0xCD, 0x12, 0x34, 0xCD, 0x43, 0x21, 0xCE, 0x05, 0x35, 0x34, 0x56, 0x01, 0x8F,
                 0xA5, 0x77, 0xCC, 0xD7, 0x9B, 0x4C, 0xF4, 0x00>>
    end

    test "message too large is split into chunks" do
      hello = %Hello{
        board_identifier: "Tester",
        board_version: 17_185,
        boot_id: 87_372_886,
        ppnet_version: 1,
        unique_id: "TestRunner",
        version: 4660
      }

      [encoded_header | encoded_chunks] = PPNet.encode_message(hello, limit: 35)

      assert %{messages: [decoded_header | decoded_chunks], errors: []} =
               [encoded_header | encoded_chunks] |> Enum.join() |> PPNet.parse()

      assert decoded_header.message_module == Hello
      assert decoded_header.total_chunks == length(decoded_chunks)

      assert Enum.all?(decoded_chunks, fn decoded_chunk ->
               decoded_chunk.transaction_id == decoded_header.transaction_id
             end)

      assert PPNet.chuncked_to_message([decoded_header | decoded_chunks]) == {:ok, hello}
    end
  end

  describe "decode PPNet.Message.SingleCounter" do
    test "parse/1 with valid binary data" do
      payload =
        <<0x08, 0x02, 0x94, 0xA3, 0x62, 0x61, 0x72, 0x2A, 0x0C, 0xCD, 0x05, 0xDC, 0xE8, 0x63, 0xFF, 0xB3, 0x4D, 0x07,
          0x21, 0xD6, 0x00>>

      assert %{
               messages: [
                 %SingleCounter{
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
          <<0x08, 0x02, 0x94, 0xA3, 0x62, 0x61, 0x72, 0x2A, 0x0C, 0xCD, 0x05, 0xDC, 0xE8, 0x63, 0xFF, 0xB3, 0x4D, 0x07,
            0x21, 0xD6, 0x00>>
        )

      assert PPNet.parse(payload) ==
               %{
                 messages: [
                   %SingleCounter{
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
                   data: %{payload: <<2, 24, 15, 4, 69, 148, 160>>},
                   message: "Failed to parse message",
                   reason: {:cobs, "Offset byte specifies more bytes than available"}
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

      assert PPNet.encode_message(message) ==
               <<0x08, 0x02, 0x94, 0xA3, 0x62, 0x61, 0x72, 0x2A, 0x0C, 0xCD, 0x05, 0xDC, 0xE8, 0x63, 0xFF, 0xB3, 0x4D,
                 0x07, 0x21, 0xD6, 0x00>>
    end
  end

  describe "decode PPNet.Message.Ping" do
    test "parse/1 with valid binary data" do
      payload =
        <<0x06, 0x03, 0x93, 0xCB, 0x40, 0x39, 0x01, 0x01, 0x01, 0x01, 0x01, 0x0D, 0xCD, 0x03, 0xE8, 0x80, 0x40, 0xE0,
          0xB6, 0xBA, 0xD7, 0x5A, 0x13, 0xB6, 0x00>>

      assert %{
               messages: [
                 %Ping{
                   temperature: 25.0,
                   uptime_ms: 1000,
                   extra: %{}
                 }
               ],
               errors: []
             } = PPNet.parse(payload)
    end

    test "parse/1 with valid binary data and extra is present" do
      payload =
        <<0x06, 0x03, 0x93, 0xCB, 0x40, 0x39, 0x01, 0x01, 0x01, 0x01, 0x01, 0x1D, 0xCD, 0x03, 0xE8, 0x82, 0xA3, 0x66,
          0x6F, 0x6F, 0xA3, 0x62, 0x61, 0x7A, 0xA3, 0x62, 0x61, 0x7A, 0xA3, 0x62, 0x61, 0x72, 0xFB, 0x8E, 0x9E, 0x9A,
          0x2E, 0x19, 0xEA, 0x3D, 0x00>>

      assert %{
               messages: [
                 %Ping{
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

      assert PPNet.encode_message(message) ==
               <<0x06, 0x03, 0x93, 0xCB, 0x40, 0x39, 0x01, 0x01, 0x01, 0x01, 0x01, 0x0D, 0xCD, 0x03, 0xE8, 0x80, 0x40,
                 0xE0, 0xB6, 0xBA, 0xD7, 0x5A, 0x13, 0xB6, 0x00>>
    end

    test "encode/1 with valid data and extra" do
      message = %Ping{
        temperature: 25.0,
        uptime_ms: 1000,
        extra: %{foo: "bar", baz: 123}
      }

      assert PPNet.encode_message(message) ==
               <<0x06, 0x03, 0x93, 0xCB, 0x40, 0x39, 0x01, 0x01, 0x01, 0x01, 0x01, 0x19, 0xCD, 0x03, 0xE8, 0x82, 0xA3,
                 0x62, 0x61, 0x7A, 0x7B, 0xA3, 0x66, 0x6F, 0x6F, 0xA3, 0x62, 0x61, 0x72, 0x9A, 0xFC, 0x71, 0x8F, 0x84,
                 0x17, 0x3B, 0x01, 0x00>>
    end

    test "message too large is split into chunks" do
      message = %Ping{
        temperature: 25.0,
        uptime_ms: 1000,
        extra: %{"foo" => String.duplicate("a", 100)}
      }

      [encoded_header | encoded_chunks] = PPNet.encode_message(message, limit: 25)

      assert %{messages: [decoded_header | decoded_chunks], errors: []} =
               [encoded_header | encoded_chunks] |> Enum.join() |> PPNet.parse()

      assert decoded_header.message_module == Ping
      assert decoded_header.total_chunks == length(decoded_chunks)

      assert Enum.all?(decoded_chunks, fn decoded_chunk ->
               decoded_chunk.transaction_id == decoded_header.transaction_id
             end)

      assert PPNet.chuncked_to_message([decoded_header | decoded_chunks]) == {:ok, message}
    end
  end

  describe "decode PPNet.Message.Event" do
    test "parse/1 with valid binary data" do
      payload =
        <<0x2B, 0x04, 0x92, 0xAC, 0x73, 0x65, 0x6E, 0x73, 0x6F, 0x72, 0x5F, 0x61, 0x6C, 0x65, 0x72, 0x74, 0x82, 0xA5,
          0x76, 0x61, 0x6C, 0x75, 0x65, 0x64, 0xA9, 0x73, 0x65, 0x6E, 0x73, 0x6F, 0x72, 0x5F, 0x69, 0x64, 0x01, 0xB4,
          0xA2, 0x69, 0xF2, 0x1D, 0xFE, 0x19, 0xAE, 0x00>>

      assert %{
               messages: [
                 %Event{
                   data: %{"sensor_id" => 1, "value" => 100},
                   kind: "sensor_alert"
                 }
               ],
               errors: []
             } = PPNet.parse(payload)
    end
  end

  describe "encode PPNet.Message.Event" do
    test "encode/1 with valid data" do
      assert PPNet.encode_message(%Event{
               kind: "sensor_alert",
               data: %{sensor_id: 1, value: 100}
             }) ==
               <<0x2B, 0x04, 0x92, 0xAC, 0x73, 0x65, 0x6E, 0x73, 0x6F, 0x72, 0x5F, 0x61, 0x6C, 0x65, 0x72, 0x74, 0x82,
                 0xA9, 0x73, 0x65, 0x6E, 0x73, 0x6F, 0x72, 0x5F, 0x69, 0x64, 0x01, 0xA5, 0x76, 0x61, 0x6C, 0x75, 0x65,
                 0x64, 0xED, 0x65, 0xD2, 0xCB, 0x07, 0xD2, 0xFC, 0x61, 0x00>>
    end

    test "message too large is split into chunks" do
      message = %Event{
        kind: "sensor_alert",
        data: %{"sensor_id" => 1, "value" => String.duplicate("a", 100)}
      }

      [encoded_header | encoded_chunks] = PPNet.encode_message(message, limit: 35)

      assert %{messages: [decoded_header | decoded_chunks], errors: []} =
               [encoded_header | encoded_chunks] |> Enum.join() |> PPNet.parse()

      assert decoded_header.message_module == Event
      assert decoded_header.total_chunks == length(decoded_chunks)

      assert Enum.all?(decoded_chunks, fn decoded_chunk ->
               decoded_chunk.transaction_id == decoded_header.transaction_id
             end)

      assert PPNet.chuncked_to_message([decoded_header | decoded_chunks]) == {:ok, message}
    end
  end

  describe "encode image" do
    test "encode/1 with valid data limited to 200 bytes" do
      image = File.read!("test/support/static/image.webp")
      [header | chunks] = PPNet.encode_message(%Image{data: image, format: :webp}, limit: 200)

      assert %{
               messages: [
                 %ChunckedMessageHeader{
                   message_module: Image,
                   transaction_id: transaction_id,
                   datetime: %DateTime{},
                   total_chunks: 150
                 } = decoded_header
               ],
               errors: []
             } = PPNet.parse(header)

      assert is_integer(transaction_id)

      decoded_chunks =
        Enum.map(chunks, fn chunk ->
          assert %{
                   messages: [
                     %ChunckedMessageBody{
                       transaction_id: ^transaction_id,
                       chunk_index: chunk_index,
                       chunk_size: chunk_size,
                       chunk_data: chunk_data
                     } = decoded_chunk
                   ],
                   errors: []
                 } = PPNet.parse(chunk)

          assert is_integer(transaction_id)
          assert is_integer(chunk_index)
          assert is_binary(chunk_data)
          assert byte_size(chunk_data) == chunk_size
          assert byte_size(chunk) <= 200

          decoded_chunk
        end)

      assert {:ok, %Image{data: ^image, format: :webp}} =
               PPNet.chuncked_to_message([decoded_header | decoded_chunks])
    end

    test "encode/1 with valid data without limit uses default limit of 254" do
      image = File.read!("test/support/static/image.webp")

      messages =
        %Image{data: image, format: :webp}
        |> PPNet.encode_message()
        |> Enum.join()

      assert %{
               errors: [],
               messages: [
                 %ChunckedMessageHeader{
                   message_module: Image,
                   transaction_id: transaction_id,
                   total_chunks: 115
                 } = header
                 | chunks
               ]
             } = PPNet.parse(messages)

      assert length(chunks) == header.total_chunks

      assert Enum.all?(Enum.with_index(chunks), fn {chunk, index} ->
               assert %ChunckedMessageBody{
                        chunk_data: chunk_data,
                        chunk_size: chunk_size,
                        chunk_index: ^index,
                        transaction_id: ^transaction_id
                      } = chunk

               assert is_binary(chunk_data)
               assert chunk_size <= 254
             end)

      assert {:ok, %Image{data: ^image, format: :webp}} =
               PPNet.chuncked_to_message([header | chunks])
    end
  end

  describe "decode image" do
    test "parse/1 with valid binary data" do
      payload = File.read!("test/support/static/image.webp")

      assert %{
               messages: [
                 %ChunckedMessageHeader{
                   message_module: Image,
                   transaction_id: transaction_id,
                   total_chunks: 150,
                   datetime: %DateTime{}
                 }
                 | chunks
               ],
               errors: []
             } =
               %Image{data: payload, format: :webp}
               |> PPNet.encode_message(limit: 200)
               |> Enum.join()
               |> PPNet.parse()

      assert Enum.all?(chunks, fn chunk ->
               %ChunckedMessageBody{
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
                   data: %{payload: ""},
                   message: "Failed to parse message",
                   reason: {:reed_solomon, %ErlangError{original: :nif_panicked, reason: nil}}
                 },
                 %PPNet.ParseError{
                   data: %{payload: <<24, 15, 4, 69, 148, 160>>},
                   message: "Failed to parse message",
                   reason: {:cobs, "Offset byte specifies more bytes than available"}
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
      [image_header | image_chunks] = PPNet.encode_message(%Image{data: image, format: :webp}, limit: 200)

      wrong_message =
        <<0x04, 0xFE, 0xA, 0xE, 0x68, 0x92, 0xAC, 0x73, 0x65, 0x6E, 0x73, 0x6F, 0x72, 0x5F, 0x00>>

      messages =
        Enum.join([image_header, ping] ++ image_chunks ++ [wrong_message, single_counter, hello, event])

      assert %{
               messages: messages,
               errors: [
                 %PPNet.ParseError{
                   data: %{
                     payload: <<4, 254, 10, 14, 104, 146, 172, 115, 101, 110, 115, 111, 114, 95>>
                   },
                   message: "Failed to parse message",
                   reason: {:cobs, "Offset byte specifies more bytes than available"}
                 }
               ]
             } = PPNet.parse(messages)

      assert [
               %ChunckedMessageHeader{
                 message_module: Image,
                 transaction_id: transaction_id,
                 total_chunks: total_chunks
               }
               | rest_1
             ] = messages

      assert [
               %Ping{
                 temperature: 25.0,
                 uptime_ms: 1000
               }
               | rest_2
             ] = rest_1

      {chunks, rest_3} = Enum.split(rest_2, total_chunks)

      assert Enum.all?(Enum.with_index(chunks), fn {chunk, index} ->
               assert %ChunckedMessageBody{
                        chunk_data: _chunk_data,
                        chunk_size: _chunk_size,
                        chunk_index: ^index,
                        transaction_id: ^transaction_id
                      } = chunk
             end)

      assert [
               %SingleCounter{
                 duration_ms: 1500,
                 pulses: 0,
                 value: 42,
                 kind: "bar"
               }
               | rest_4
             ] = rest_3

      assert [
               %Hello{
                 board_identifier: "Tester",
                 board_version: 17_185,
                 boot_id: 87_372_886,
                 ppnet_version: 1,
                 unique_id: "TestRunner",
                 version: 4660
               }
               | rest_5
             ] = rest_4

      assert [
               %Event{
                 kind: "sensor_alert",
                 data: %{"sensor_id" => 1, "value" => 100}
               }
             ] = rest_5
    end
  end
end
