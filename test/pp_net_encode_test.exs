defmodule PpnetEncodeTest do
  use ExUnit.Case, async: true

  alias PPNet.Message.ChunkedMessageBody
  alias PPNet.Message.ChunkedMessageHeader
  alias PPNet.Message.Event
  alias PPNet.Message.Hello
  alias PPNet.Message.Image
  alias PPNet.Message.Ping
  alias PPNet.Message.SingleCounter

  describe "encode PPNet.Message.Hello" do
    test "encode/1 with valid data" do
      message =
        %Hello{
          board_identifier: "Tester",
          board_version: 17_185,
          boot_id: 87_372_886,
          ppnet_version: 1,
          unique_id: "TestRunner",
          version: 4660,
          datetime: ~U[2026-03-26 21:00:55.352750Z]
        }

      assert PPNet.encode_message(message) ==
               <<0x2E, 0x01, 0x97, 0xAA, 0x54, 0x65, 0x73, 0x74, 0x52, 0x75, 0x6E, 0x6E, 0x65, 0x72, 0xA6, 0x54, 0x65,
                 0x73, 0x74, 0x65, 0x72, 0xCD, 0x12, 0x34, 0xCD, 0x43, 0x21, 0xCE, 0x05, 0x35, 0x34, 0x56, 0x01, 0xCE,
                 0x69, 0xC5, 0x9E, 0x87, 0x25, 0xD8, 0xC2, 0x4C, 0x7E, 0x8B, 0x0F, 0x96, 0x00>>
    end

    test "message too large is split into chunks" do
      hello = %Hello{
        board_identifier: "Tester",
        board_version: 17_185,
        boot_id: 87_372_886,
        ppnet_version: 1,
        unique_id: "TestRunner",
        version: 4660,
        datetime: ~U[2026-03-26 21:00:55Z]
      }

      [encoded_header | encoded_chunks] = PPNet.encode_message(hello, limit: 35)

      assert %{messages: [decoded_header | decoded_chunks], errors: []} =
               [encoded_header | encoded_chunks]
               |> Enum.join()
               |> PPNet.parse()

      assert decoded_header.message_module == Hello
      assert decoded_header.total_chunks == length(decoded_chunks)

      assert Enum.all?(decoded_chunks, fn decoded_chunk ->
               decoded_chunk.transaction_id == decoded_header.transaction_id
             end)

      assert PPNet.chunked_to_message([decoded_header | decoded_chunks]) == {:ok, hello}
    end

    test "pack/1 with invalid struct returns error" do
      # negative version violates non-negative integer guard
      assert {:error, %PPNet.PackError{reason: :invalid_struct}} =
               Hello.pack(%Hello{
                 unique_id: "TestRunner",
                 board_identifier: "Tester",
                 version: -1,
                 board_version: 17_185,
                 boot_id: 87_372_886,
                 ppnet_version: 1,
                 datetime: ~U[2026-03-26 21:00:55.352750Z]
               })

      # unique_id not a binary
      assert {:error, %PPNet.PackError{reason: :invalid_struct}} =
               Hello.pack(%Hello{
                 unique_id: 12_345,
                 board_identifier: "Tester",
                 version: 1,
                 board_version: 17_185,
                 boot_id: 87_372_886,
                 ppnet_version: 1,
                 datetime: ~U[2026-03-26 21:00:55.352750Z]
               })
    end
  end

  describe "encode PPNet.Message.SingleCounter" do
    test "encode/1 with valid data" do
      message = %SingleCounter{
        duration_ms: 1500,
        kind: "bar",
        pulses: 0,
        value: 42,
        datetime: ~U[2026-03-27 12:58:06Z]
      }

      assert PPNet.encode_message(message) ==
               <<0x08, 0x02, 0x95, 0xA3, 0x62, 0x61, 0x72, 0x2A, 0x11, 0xCD, 0x05, 0xDC, 0xCE, 0x69, 0xC6, 0x7E, 0xDE,
                 0x34, 0x40, 0x8D, 0x2C, 0x55, 0xEE, 0xF9, 0x2D, 0x00>>
    end

    test "pack/1 with invalid struct returns error" do
      # kind must be a binary string
      assert {:error, %PPNet.PackError{reason: :invalid_struct}} =
               SingleCounter.pack(%SingleCounter{kind: 123, value: 42, pulses: 0, duration_ms: 1500, datetime: nil})

      # duration_ms must be an integer
      assert {:error, %PPNet.PackError{reason: :invalid_struct}} =
               SingleCounter.pack(%SingleCounter{
                 kind: "bar",
                 value: 42,
                 pulses: 0,
                 duration_ms: "1500ms",
                 datetime: nil
               })
    end

    test "encode_message/2 with limit above maximum clamps to 254" do
      message = %SingleCounter{kind: "a", value: 0, pulses: 0, duration_ms: 0, datetime: DateTime.utc_now()}
      assert PPNet.encode_message(message, limit: 9999) == PPNet.encode_message(message)
    end

    test "encode_message/2 with limit below minimum clamps to 17" do
      message = %SingleCounter{kind: "a", value: 0, pulses: 0, duration_ms: 0, datetime: DateTime.utc_now()}
      assert PPNet.encode_message(message, limit: 5) == PPNet.encode_message(message, limit: 17)
    end
  end

  describe "encode PPNet.Message.Ping" do
    test "encode/1 with valid data" do
      message =
        %Ping{
          session_id: "5388724c-457e-4332-a98c-e67b2053662c",
          temperature: 25.0,
          uptime_ms: 100_000,
          location: %{lat: 40.712812345, lon: -74.006012345, accuracy: 10_000},
          cpu: 0.5,
          tpu_memory_percent: 50,
          tpu_ping_ms: 100,
          wifi: [
            %{mac: "00:1A:2B:3C:4D:5E", rssi: -42},
            %{mac: "01:23:45:67:89:AB", rssi: -55}
          ],
          datetime: ~U[2026-03-27 16:25:12Z],
          storage: %{total: 1000, used: 500}
        }

      assert PPNet.encode_message(message) ==
               <<0x04, 0x03, 0x9B, 0xDC, 0x19, 0x10, 0x53, 0xCC, 0x88, 0x72, 0x4C, 0x45, 0x7E, 0x43, 0x32, 0xCC, 0xA9,
                 0xCC, 0x8C, 0xCC, 0xE6, 0x7B, 0x20, 0x53, 0x66, 0x2C, 0xCB, 0x40, 0x39, 0x01, 0x01, 0x01, 0x01, 0x01,
                 0x02, 0xCE, 0x1D, 0x01, 0x86, 0xA0, 0x93, 0xCB, 0x40, 0x44, 0x5B, 0x3D, 0x6F, 0x56, 0xFA, 0xE4, 0xCB,
                 0xC0, 0x52, 0x80, 0x62, 0x81, 0x9A, 0x49, 0x6D, 0xCD, 0x27, 0x10, 0xCB, 0x3F, 0xE0, 0x01, 0x01, 0x01,
                 0x01, 0x01, 0x05, 0x32, 0x64, 0x92, 0xA7, 0x24, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E, 0xD6, 0xA7, 0x01, 0x23,
                 0x45, 0x67, 0x89, 0xAB, 0xC9, 0x92, 0xCD, 0x03, 0xE8, 0xCD, 0x01, 0xF4, 0xCE, 0x69, 0xC6, 0xAF, 0x68,
                 0x80, 0x5D, 0xA5, 0xE1, 0x9E, 0x28, 0xB5, 0xED, 0xEC, 0x00>>
    end

    test "encode/1 with valid data and extra" do
      message = %Ping{
        session_id: "5388724c-457e-4332-a98c-e67b2053662c",
        temperature: 25.0,
        uptime_ms: 1000,
        extra: %{foo: "bar", baz: 123},
        location: %{lat: 40.712812345, lon: -74.006012345, accuracy: 10_000},
        cpu: 0.5,
        tpu_memory_percent: 50,
        tpu_ping_ms: 100,
        wifi: [],
        datetime: ~U[2026-03-27 16:25:12Z],
        storage: %{total: 1000, used: 500}
      }

      assert PPNet.encode_message(message) ==
               <<0x04, 0x03, 0x9B, 0xDC, 0x19, 0x10, 0x53, 0xCC, 0x88, 0x72, 0x4C, 0x45, 0x7E, 0x43, 0x32, 0xCC, 0xA9,
                 0xCC, 0x8C, 0xCC, 0xE6, 0x7B, 0x20, 0x53, 0x66, 0x2C, 0xCB, 0x40, 0x39, 0x01, 0x01, 0x01, 0x01, 0x01,
                 0x1D, 0xCD, 0x03, 0xE8, 0x93, 0xCB, 0x40, 0x44, 0x5B, 0x3D, 0x6F, 0x56, 0xFA, 0xE4, 0xCB, 0xC0, 0x52,
                 0x80, 0x62, 0x81, 0x9A, 0x49, 0x6D, 0xCD, 0x27, 0x10, 0xCB, 0x3F, 0xE0, 0x01, 0x01, 0x01, 0x01, 0x01,
                 0x25, 0x32, 0x64, 0x90, 0x92, 0xCD, 0x03, 0xE8, 0xCD, 0x01, 0xF4, 0xCE, 0x69, 0xC6, 0xAF, 0x68, 0x82,
                 0xA3, 0x62, 0x61, 0x7A, 0x7B, 0xA3, 0x66, 0x6F, 0x6F, 0xA3, 0x62, 0x61, 0x72, 0x31, 0x0A, 0xE5, 0xB4,
                 0x2B, 0xC1, 0xC1, 0x01, 0x00>>
    end

    test "message too large is split into chunks" do
      message = %Ping{
        session_id: "5388724c-457e-4332-a98c-e67b2053662c",
        temperature: 25.0,
        uptime_ms: 1_262_304_000_000,
        location: %{lat: 40.712812345, lon: -74.006012345, accuracy: 10_000},
        cpu: 0.5,
        tpu_memory_percent: 50,
        tpu_ping_ms: 100,
        wifi: [
          %{mac: "00:1A:2B:3C:4D:5E", rssi: -42},
          %{mac: "01:23:45:67:89:AB", rssi: -55},
          %{mac: "DC:FE:01:23:45:67", rssi: -70},
          %{mac: "12:34:56:78:9A:BC", rssi: -65},
          %{mac: "A1:B2:C3:D4:E5:F6", rssi: -80},
          %{mac: "9A:BC:DE:F0:12:34", rssi: -60},
          %{mac: "FE:DC:BA:98:76:54", rssi: -75},
          %{mac: "02:04:06:08:0A:0C", rssi: -49},
          %{mac: "F0:E1:D2:C3:B4:A5", rssi: -58},
          %{mac: "55:44:33:22:11:00", rssi: -61}
        ],
        storage: %{total: 1000, used: 500},
        datetime: ~U[2026-03-27 16:25:12Z],
        extra: %{
          "foo" => String.duplicate("a", 100),
          "bar" => String.duplicate("b", 100),
          "baz" => String.duplicate("c", 100)
        }
      }

      [encoded_header | encoded_chunks] = PPNet.encode_message(message, limit: 200)

      assert %{messages: [decoded_header | decoded_chunks], errors: []} =
               [encoded_header | encoded_chunks]
               |> Enum.join()
               |> PPNet.parse()

      assert decoded_header.message_module == Ping
      assert decoded_header.total_chunks == length(decoded_chunks)

      assert Enum.all?(decoded_chunks, fn decoded_chunk ->
               decoded_chunk.transaction_id == decoded_header.transaction_id
             end)

      assert PPNet.chunked_to_message([decoded_header | decoded_chunks]) == {:ok, message}
    end

    test "pack/1 with invalid struct returns error" do
      # temperature must be a float
      assert {:error, %PPNet.PackError{reason: :invalid_struct}} =
               Ping.pack(%Ping{
                 session_id: "5388724c-457e-4332-a98c-e67b2053662c",
                 temperature: 25,
                 uptime_ms: 1000,
                 location: %{lat: 40.0, lon: -74.0, accuracy: 10_000},
                 cpu: 0.5,
                 tpu_memory_percent: 50,
                 tpu_ping_ms: 100,
                 wifi: [],
                 datetime: ~U[2026-03-27 16:25:12Z],
                 storage: %{total: 1000, used: 500}
               })

      # cpu must be between 0.0 and 1.0
      assert {:error, %PPNet.PackError{reason: :invalid_struct}} =
               Ping.pack(%Ping{
                 session_id: "5388724c-457e-4332-a98c-e67b2053662c",
                 temperature: 25.0,
                 uptime_ms: 1000,
                 location: %{lat: 40.0, lon: -74.0, accuracy: 10_000},
                 cpu: 1.5,
                 tpu_memory_percent: 50,
                 tpu_ping_ms: 100,
                 wifi: [],
                 datetime: ~U[2026-03-27 16:25:12Z],
                 storage: %{total: 1000, used: 500}
               })
    end
  end

  describe "encode PPNet.Message.Event" do
    test "encode/1 with valid data" do
      assert PPNet.encode_message(%Event{
               kind: :detection,
               data: %{sensor_id: 1, value: 100},
               datetime: ~U[2026-03-27 18:46:39Z]
             }) ==
               <<0x24, 0x04, 0x93, 0x01, 0x82, 0xA9, 0x73, 0x65, 0x6E, 0x73, 0x6F, 0x72, 0x5F, 0x69, 0x64, 0x01, 0xA5,
                 0x76, 0x61, 0x6C, 0x75, 0x65, 0x64, 0xCE, 0x69, 0xC6, 0xD0, 0x8F, 0x89, 0x5B, 0x7B, 0xB2, 0xB9, 0x23,
                 0xC1, 0x2C, 0x00>>
    end

    test "encode/1 encode sensor alert map data" do
      image_id =
        "997a6060-d384-4a35-8507-3eead1aed51e"
        |> UUID.string_to_binary!()
        |> :binary.bin_to_list()

      data = %{
        "image_id" => image_id,
        "d" => [
          %{
            "bbox" => [339.9502060711384, 152.13321420550346, 86.00608867406845, 85.85731941461563],
            "c" => 0,
            "s" => 0.53912
          },
          %{
            "bbox" => [339.9502060711384, 152.13321420550346, 86.00608867406845, 85.85731941461563],
            "c" => 0,
            "s" => 0.53912
          },
          %{
            "bbox" => [339.9502060711384, 152.13321420550346, 86.00608867406845, 85.85731941461563],
            "c" => 0,
            "s" => 0.53912
          }
        ]
      }

      event = %Event{
        kind: :detection,
        data: data,
        datetime: ~U[2026-03-27 18:46:39Z]
      }

      assert PPNet.encode_message(event) ==
               <<0x0F, 0x04, 0x93, 0x01, 0x82, 0xA8, 0x69, 0x6D, 0x61, 0x67, 0x65, 0x5F, 0x69, 0x64, 0xDC, 0x2B, 0x10,
                 0xCC, 0x99, 0x7A, 0x60, 0x60, 0xCC, 0xD3, 0xCC, 0x84, 0x4A, 0x35, 0xCC, 0x85, 0x07, 0x3E, 0xCC, 0xEA,
                 0xCC, 0xD1, 0xCC, 0xAE, 0xCC, 0xD5, 0x1E, 0xA1, 0x64, 0x93, 0x83, 0xA1, 0x73, 0xCB, 0x3F, 0xE1, 0x40,
                 0x78, 0x96, 0x13, 0xD3, 0x1C, 0xA1, 0x63, 0x0E, 0xA4, 0x62, 0x62, 0x6F, 0x78, 0x94, 0xCB, 0x40, 0x75,
                 0x3F, 0x34, 0x0B, 0x48, 0x01, 0x08, 0xCB, 0x40, 0x63, 0x04, 0x43, 0x4A, 0x70, 0x01, 0x08, 0xCB, 0x40,
                 0x55, 0x80, 0x63, 0xC1, 0xC0, 0x01, 0x08, 0xCB, 0x40, 0x55, 0x76, 0xDE, 0x52, 0x40, 0x01, 0x0F, 0x83,
                 0xA1, 0x73, 0xCB, 0x3F, 0xE1, 0x40, 0x78, 0x96, 0x13, 0xD3, 0x1C, 0xA1, 0x63, 0x0E, 0xA4, 0x62, 0x62,
                 0x6F, 0x78, 0x94, 0xCB, 0x40, 0x75, 0x3F, 0x34, 0x0B, 0x48, 0x01, 0x08, 0xCB, 0x40, 0x63, 0x04, 0x43,
                 0x4A, 0x70, 0x01, 0x08, 0xCB, 0x40, 0x55, 0x80, 0x63, 0xC1, 0xC0, 01, 0x08, 0xCB, 0x40, 0x55, 0x76,
                 0xDE, 0x52, 0x40, 0x01, 0x0F, 0x83, 0xA1, 0x73, 0xCB, 0x3F, 0xE1, 0x40, 0x78, 0x96, 0x13, 0xD3, 0x1C,
                 0xA1, 0x63, 0x0E, 0xA4, 0x62, 0x62, 0x6F, 0x78, 0x94, 0xCB, 0x40, 0x75, 0x3F, 0x34, 0x0B, 0x48, 0x01,
                 0x08, 0xCB, 0x40, 0x63, 0x04, 0x43, 0x4A, 0x70, 0x01, 0x08, 0xCB, 0x40, 0x55, 0x80, 0x63, 0xC1, 0xC0,
                 0x01, 0x08, 0xCB, 0x40, 0x55, 0x76, 0xDE, 0x52, 0x40, 0x01, 0x0E, 0xCE, 0x69, 0xC6, 0xD0, 0x8F, 0xB9,
                 0x92, 0x72, 0xAE, 0x75, 0x64, 0x58, 0x12, 0x00>>
    end

    test "message too large is split into chunks" do
      message = %Event{
        kind: :detection,
        data: %{"sensor_id" => 1, "value" => String.duplicate("a", 100)},
        datetime: ~U[2026-03-27 18:46:39Z]
      }

      [encoded_header | encoded_chunks] = PPNet.encode_message(message, limit: 35)

      assert %{messages: [decoded_header | decoded_chunks], errors: []} =
               [encoded_header | encoded_chunks]
               |> Enum.join()
               |> PPNet.parse()

      assert decoded_header.message_module == Event
      assert decoded_header.total_chunks == length(decoded_chunks)

      assert Enum.all?(decoded_chunks, fn decoded_chunk ->
               decoded_chunk.transaction_id == decoded_header.transaction_id
             end)

      assert PPNet.chunked_to_message([decoded_header | decoded_chunks]) == {:ok, message}
    end

    test "pack/1 with invalid struct returns error" do
      # kind must be a valid atom (:detection), not an unknown one
      assert {:error, %PPNet.PackError{reason: :invalid_struct}} =
               Event.pack(%Event{kind: :unknown_event, data: %{"sensor_id" => 1}, datetime: DateTime.utc_now()})

      # data must be a map
      assert {:error, %PPNet.PackError{reason: :invalid_struct}} =
               Event.pack(%Event{kind: :detection, data: ["not", "a", "map"], datetime: DateTime.utc_now()})
    end
  end

  describe "encode image" do
    test "encode/1 with valid data limited to 200 bytes" do
      image = File.read!("test/support/static/image.webp")

      id = UUID.uuid4()

      [header | chunks] =
        PPNet.encode_message(
          %Image{
            id: id,
            data: image,
            format: :webp
          },
          limit: 200
        )

      assert %{
               messages: [
                 %ChunkedMessageHeader{
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
                     %ChunkedMessageBody{
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

      assert {:ok, %Image{id: ^id, data: ^image, format: :webp}} =
               PPNet.chunked_to_message([decoded_header | decoded_chunks])
    end

    test "encode/1 with valid data without limit uses default limit of 254" do
      image = File.read!("test/support/static/image.webp")

      messages =
        %Image{id: UUID.uuid4(), data: image, format: :webp}
        |> PPNet.encode_message()
        |> Enum.join()

      assert %{
               errors: [],
               messages: [
                 %ChunkedMessageHeader{
                   message_module: Image,
                   transaction_id: transaction_id,
                   total_chunks: 116
                 } = header
                 | chunks
               ]
             } = PPNet.parse(messages)

      assert length(chunks) == header.total_chunks

      assert Enum.all?(Enum.with_index(chunks), fn {chunk, index} ->
               assert %ChunkedMessageBody{
                        chunk_data: chunk_data,
                        chunk_size: chunk_size,
                        chunk_index: ^index,
                        transaction_id: ^transaction_id
                      } = chunk

               assert is_binary(chunk_data)
               assert chunk_size <= 254
             end)

      assert {:ok, %Image{data: ^image, format: :webp}} =
               PPNet.chunked_to_message([header | chunks])
    end

    test "pack/1 with invalid struct returns error" do
      # format :gif is not a supported format
      assert {:error, %PPNet.PackError{reason: :invalid_struct}} =
               Image.pack(%Image{
                 id: "00000000-0000-0000-0000-000000000000",
                 format: :gif,
                 data: "image data"
               })

      # id must be a valid UUID — 10-byte string is neither a 16-byte raw UUID nor a formatted one
      assert {:error, %PPNet.PackError{}} =
               Image.pack(%Image{
                 id: "short-uuid",
                 format: :webp,
                 data: "image data"
               })
    end
  end

  describe "encode PPNet.Message.ChunkedMessageBody" do
    test "pack/1 with invalid struct returns error" do
      # negative transaction_id violates guard
      assert {:error, %PPNet.PackError{reason: :invalid_struct}} =
               ChunkedMessageBody.pack(%ChunkedMessageBody{
                 transaction_id: -1,
                 chunk_index: 0,
                 chunk_size: 5,
                 chunk_data: "hello"
               })

      # chunk_size declared as 100 but chunk_data is only 2 bytes — triggers rescue
      assert {:error, %PPNet.PackError{}} =
               ChunkedMessageBody.pack(%ChunkedMessageBody{
                 transaction_id: 0,
                 chunk_index: 0,
                 chunk_size: 100,
                 chunk_data: "hi"
               })
    end
  end

  describe "The following tests are only to remind me approximately of the message sizes" do
    test "encode a Ping message" do
      message = %Ping{
        session_id: "5388724c-457e-4332-a98c-e67b2053662c",
        temperature: 60.0,
        uptime_ms: 300_000_000_000,
        location: %{lat: 89.123456789, lon: 179.987654321, accuracy: 10},
        cpu: 1.0,
        tpu_memory_percent: 100,
        tpu_ping_ms: 600,
        wifi: [
          %{mac: "01:23:45:67:89:AB", rssi: -5},
          %{mac: "00:1A:2B:3C:4D:5E", rssi: -12},
          %{mac: "DC:FE:01:23:45:67", rssi: -20},
          %{mac: "12:34:56:78:9A:BC", rssi: -25},
          %{mac: "A1:B2:C3:D4:E5:F6", rssi: -30},
          %{mac: "9A:BC:DE:F0:12:34", rssi: -43},
          %{mac: "FE:DC:BA:98:76:54", rssi: -55},
          %{mac: "02:04:06:08:0A:0C", rssi: -69},
          %{mac: "F0:E1:D2:C3:B4:A5", rssi: -78},
          %{mac: "55:44:33:22:11:00", rssi: -99}
        ],
        storage: %{total: 4_294_967, used: 4_000_000},
        datetime: ~U[2026-03-27 16:25:12Z],
        extra: %{}
      }

      assert byte_size(PPNet.encode_message(message)) == 184
    end

    test "encode a Hello message" do
      message = %Hello{
        unique_id: "5388724c-457e-4332-a98c-e67b2053662c",
        board_identifier: "Raspberry-Pi-Zero-2W",
        version: 10_000,
        board_version: 10_000,
        boot_id: 1_000_000_000,
        ppnet_version: 5,
        datetime: ~U[2026-03-27 16:25:12Z]
      }

      assert byte_size(PPNet.encode_message(message)) == 88
    end

    test "encode a SingleCounter message" do
      message = %SingleCounter{
        kind: "energy-meter-kwh",
        value: 999_999,
        pulses: 10_000,
        duration_ms: 3_600_000,
        datetime: ~U[2026-03-27 16:25:12Z]
      }

      assert byte_size(PPNet.encode_message(message)) == 47
    end

    test "encode an Event message" do
      image_id =
        "997a6060-d384-4a35-8507-3eead1aed51e"
        |> UUID.string_to_binary!()
        |> :binary.bin_to_list()

      message = %Event{
        kind: :detection,
        data: %{
          "image_id" => image_id,
          "d" => [
            %{
              "bbox" => [339.9502060711384, 152.13321420550346, 86.00608867406845, 85.85731941461563],
              "c" => 0,
              "s" => 0.53912
            },
            %{
              "bbox" => [339.9502060711384, 152.13321420550346, 86.00608867406845, 85.85731941461563],
              "c" => 0,
              "s" => 0.53912
            },
            %{
              "bbox" => [339.9502060711384, 152.13321420550346, 86.00608867406845, 85.85731941461563],
              "c" => 0,
              "s" => 0.53912
            }
          ]
        },
        datetime: ~U[2026-03-27 18:46:39Z]
      }

      assert byte_size(PPNet.encode_message(message)) == 229
    end
  end
end
