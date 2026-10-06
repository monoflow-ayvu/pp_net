# credo:disable-for-this-file Credo.Check.Design.DuplicatedCode
defmodule PpnetEncodeTest do
  use ExUnit.Case, async: true

  alias PPNet.Message.ChunkedMessageAck
  alias PPNet.Message.ChunkedMessageBody
  alias PPNet.Message.ChunkedMessageHeader
  alias PPNet.Message.ConfigAck
  alias PPNet.Message.ConfigData
  alias PPNet.Message.Event
  alias PPNet.Message.Hello
  alias PPNet.Message.Image
  alias PPNet.Message.Ping
  alias PPNet.Message.SingleCounter

  @full_config "test/support/static/config.json"
               |> File.read!()
               |> Jason.decode!()

  @config_data_by_kind %{
    schema: %{
      "type" => "object",
      "required" => ["version", "revision"],
      "properties" => %{
        "version" => %{"const" => 1},
        "revision" => %{"type" => "integer"}
      }
    },
    full_report: %{"version" => 1, "revision" => 7, "tz_offset_minutes" => 60},
    partial_report: %{"version" => 1, "revision" => 7, "tz_offset_minutes" => 60},
    request_schema: nil,
    request_full_config: nil,
    request_partial_config: ["/settings/tz_offset_minutes", "/cameras"],
    set_config: %{
      "version" => 1,
      "revision" => 6,
      "operations" => [
        %{"op" => "replace", "path" => "/settings/tz_offset_minutes", "value" => 0},
        %{"op" => "replace", "path" => "/cameras/1/recording_enabled", "value" => false}
      ]
    }
  }

  @invalid_config_data_by_kind %{
    # missing required "version"/"revision"
    schema: %{"type" => "object"},
    # missing "version"/"revision" fields
    full_report: %{"settings" => %{}},
    partial_report: %{"settings" => %{}},
    # must be nil — no payload allowed
    request_schema: %{"unexpected" => true},
    request_full_config: %{"unexpected" => true},
    # not a JSON Pointer (doesn't start with "/" or "#")
    request_partial_config: ["not-a-pointer"],
    # unknown "op"
    set_config: %{
      "version" => 1,
      "revision" => 1,
      "operations" => [%{"op" => "bogus", "path" => "/x"}]
    }
  }

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
               <<51, 1, 151, 170, 84, 101, 115, 116, 82, 117, 110, 110, 101, 114, 166, 84, 101, 115, 116, 101, 114, 205,
                 18, 52, 205, 67, 33, 206, 5, 53, 52, 86, 165, 48, 46, 50, 46, 48, 206, 105, 197, 158, 135, 43, 29, 69,
                 217, 24, 65, 68, 62, 0>>
    end

    test "message too large is split into chunks" do
      hello = %Hello{
        board_identifier: "Tester",
        board_version: 17_185,
        boot_id: 87_372_886,
        ppnet_version: "0.2.0",
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

    test "encode_message/2 with limit below minimum clamps to 22" do
      message = %SingleCounter{kind: "a", value: 0, pulses: 0, duration_ms: 0, datetime: DateTime.utc_now()}
      assert PPNet.encode_message(message, limit: 5) == PPNet.encode_message(message, limit: 22)
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
                 0x4A, 0x70, 0x01, 0x08, 0xCB, 0x40, 0x55, 0x80, 0x63, 0xC1, 0xC0, 0x01, 0x08, 0xCB, 0x40, 0x55, 0x76,
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

    test "pack/1 accepts data with valid UTF-8 string values" do
      assert is_binary(
               Event.pack(%Event{kind: :detection, data: %{"label" => "valid string"}, datetime: DateTime.utc_now()})
             )
    end

    test "pack/1 returns error when data contains invalid binary" do
      invalid_binary = <<0xFF, 0xFE>>

      assert {:error, %PPNet.PackError{}} =
               Event.pack(%Event{kind: :detection, data: %{"label" => invalid_binary}, datetime: DateTime.utc_now()})
    end

    test "pack/1 returns error when nested list contains invalid binary" do
      invalid_binary = <<0xFF, 0xFE>>
      refute String.valid?(invalid_binary)

      assert {:error, %PPNet.PackError{}} =
               Event.pack(%Event{
                 kind: :detection,
                 data: %{"items" => ["valid", invalid_binary]},
                 datetime: DateTime.utc_now()
               })
    end

    test "pack/1 returns error when nested map contains invalid binary" do
      invalid_binary = <<0xFF, 0xFE>>

      assert {:error, %PPNet.PackError{}} =
               Event.pack(%Event{
                 kind: :detection,
                 data: %{"nested" => %{"label" => invalid_binary}},
                 datetime: DateTime.utc_now()
               })
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
            format: :webp,
            data: image,
            datetime: ~U[2026-03-27 20:15:41Z]
          },
          limit: 200
        )

      assert %{
               messages: [
                 %ChunkedMessageHeader{
                   message_module: Image,
                   transaction_id: transaction_id,
                   datetime: %DateTime{},
                   total_chunks: 153
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
        %Image{id: UUID.uuid4(), data: image, format: :webp, datetime: ~U[2026-03-27 20:15:41Z]}
        |> PPNet.encode_message()
        |> Enum.join()

      assert %{
               errors: [],
               messages: [
                 %ChunkedMessageHeader{
                   message_module: Image,
                   transaction_id: transaction_id,
                   total_chunks: 118
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
                 data: "image data",
                 datetime: DateTime.utc_now()
               })

      # id must be a valid UUID — 10-byte string is neither a 16-byte raw UUID nor a formatted one
      assert {:error, %PPNet.PackError{}} =
               Image.pack(%Image{
                 id: "short-uuid",
                 format: :webp,
                 data: "image data",
                 datetime: DateTime.utc_now()
               })
    end

    test "pack/1 accepts H.264 data with a 3-byte Annex-B start code" do
      # Only the leading start code is validated; the trailing bytes are opaque payload.
      data = <<0, 0, 1>> <> "frame"

      packed = Image.pack(%Image{id: UUID.uuid4(), format: :h264, data: data, datetime: ~U[2026-03-27 20:15:41Z]})

      assert {:ok, %Image{format: :h264, data: ^data}} = Image.parse(packed)
    end

    test "pack/1 accepts H.264 data with a 4-byte Annex-B start code" do
      data = <<0, 0, 0, 1>> <> "frame"

      packed = Image.pack(%Image{id: UUID.uuid4(), format: :h264, data: data, datetime: ~U[2026-03-27 20:15:41Z]})

      assert {:ok, %Image{format: :h264, data: ^data}} = Image.parse(packed)
    end

    test "pack/1 rejects H.264 data without an Annex-B start code" do
      assert {:error, %PPNet.PackError{reason: :not_annex_b}} =
               Image.pack(%Image{
                 id: UUID.uuid4(),
                 format: :h264,
                 data: <<1, 2, 3, 4, 5>>,
                 datetime: DateTime.utc_now()
               })
    end
  end

  describe "encode_message/2 retransmission options" do
    setup do
      image = %Image{
        id: UUID.uuid4(),
        format: :webp,
        data: File.read!("test/support/static/image.webp"),
        datetime: ~U[2026-03-27 20:15:41Z]
      }

      {:ok, image: image}
    end

    test "when transaction_id is given, it is used instead of generating one", %{image: image} do
      [header_bin | _chunks] = PPNet.encode_message(image, limit: 200, transaction_id: 42)

      assert %{messages: [%ChunkedMessageHeader{transaction_id: 42}], errors: []} = PPNet.parse(header_bin)
    end

    test "return a tuple of transaction_id and chunks when return_transaction_id: true", %{image: image} do
      # pin transaction_id on both calls — without it each call generates its own random id,
      # so the frames (which embed transaction_id) would never compare equal
      default = PPNet.encode_message(image, limit: 200, transaction_id: 7)
      assert is_list(default)

      assert {7, ^default} = PPNet.encode_message(image, limit: 200, transaction_id: 7, return_transaction_id: true)
    end

    test "when the encoded message is a single frame, `return_transaction_id: true` is a no-op" do
      message = %SingleCounter{kind: "a", value: 0, pulses: 0, duration_ms: 0, datetime: DateTime.utc_now()}

      assert PPNet.encode_message(message, return_transaction_id: true) == PPNet.encode_message(message)
    end

    test "encoding the same message with the same transaction_id is byte-for-byte deterministic", %{image: image} do
      assert PPNet.encode_message(image, limit: 200, transaction_id: 7) ==
               PPNet.encode_message(image, limit: 200, transaction_id: 7)
    end

    test "chunk_indexes: [...] returns only those body chunks, no header", %{image: image} do
      [_header | all_chunks] = PPNet.encode_message(image, limit: 200, transaction_id: 7)

      chunks_to_resend = PPNet.encode_message(image, limit: 200, transaction_id: 7, chunk_indexes: [3, 5])

      # The chunks generated for retransmission must be exactly the same as the original chunks.
      assert chunks_to_resend == [Enum.at(all_chunks, 3), Enum.at(all_chunks, 5)]
    end

    test "chunk_indexes: [...] rejects an out-of-range index", %{image: image} do
      assert_raise ArgumentError, ~r/out of range/, fn ->
        PPNet.encode_message(image, limit: 200, transaction_id: 7, chunk_indexes: [999_999])
      end
    end

    test "encode_message_stream/2 accepts the same chunk_indexes option", %{image: image} do
      [_header | all_chunks] = PPNet.encode_message(image, limit: 200, transaction_id: 7)

      # It continues to return a stream normally.
      assert %Stream{} = stream = PPNet.encode_message_stream(image, limit: 200, transaction_id: 7, chunk_indexes: [3])
      assert Enum.to_list(stream) == [Enum.at(all_chunks, 3)]
    end

    test "return_header: true adds the header to the chunks selected by chunk_indexes", %{image: image} do
      [header | all_chunks] = PPNet.encode_message(image, limit: 200, transaction_id: 7)

      opts = [limit: 200, transaction_id: 7, chunk_indexes: [3, 5], return_header: true]

      assert PPNet.encode_message(image, opts) == [header, Enum.at(all_chunks, 3), Enum.at(all_chunks, 5)]
    end

    test "chunk_indexes: [] with return_header: true encodes only the header", %{image: image} do
      [header | _chunks] = PPNet.encode_message(image, limit: 200, transaction_id: 7)

      opts = [limit: 200, transaction_id: 7, chunk_indexes: [], return_header: true]

      assert PPNet.encode_message(image, opts) == [header]
    end

    test "return_header: false keeps chunk_indexes chunks-only", %{image: image} do
      [_header | all_chunks] = PPNet.encode_message(image, limit: 200, transaction_id: 7)

      opts = [limit: 200, transaction_id: 7, chunk_indexes: [3], return_header: false]

      assert PPNet.encode_message(image, opts) == [Enum.at(all_chunks, 3)]
    end

    test "return_header has no effect without chunk_indexes, the header is always included", %{image: image} do
      all_frames = PPNet.encode_message(image, limit: 200, transaction_id: 7)

      assert PPNet.encode_message(image, limit: 200, transaction_id: 7, return_header: true) == all_frames
      assert PPNet.encode_message(image, limit: 200, transaction_id: 7, return_header: false) == all_frames
    end

    test "return_header: true still rejects an out-of-range chunk index", %{image: image} do
      assert_raise ArgumentError, ~r/out of range/, fn ->
        PPNet.encode_message(image, limit: 200, transaction_id: 7, chunk_indexes: [999_999], return_header: true)
      end
    end

    test "encode_message_stream/2 accepts return_header", %{image: image} do
      [header | all_chunks] = PPNet.encode_message(image, limit: 200, transaction_id: 7)

      opts = [limit: 200, transaction_id: 7, chunk_indexes: [3], return_header: true]

      assert Enum.to_list(PPNet.encode_message_stream(image, opts)) == [header, Enum.at(all_chunks, 3)]
    end
  end

  describe "encode_message/2 force_chunked" do
    setup do
      {:ok,
       message: %SingleCounter{kind: "a", value: 1, pulses: 0, duration_ms: 10, datetime: ~U[2026-03-27 16:25:12Z]}}
    end

    test "a message that fits in one frame is a single binary by default", %{message: message} do
      assert is_binary(PPNet.encode_message(message))
    end

    test "force_chunked: true splits it into a header and a chunk anyway", %{message: message} do
      assert [_header_bin | _chunk_bins] = frames = PPNet.encode_message(message, force_chunked: true)

      assert %{
               messages: [%ChunkedMessageHeader{message_module: SingleCounter, total_chunks: 1} = header | chunks],
               errors: []
             } =
               PPNet.parse(frames)

      assert length(chunks) == 1
      assert PPNet.chunked_to_message([header | chunks]) == {:ok, message}
    end

    test "force_chunked: true works with transaction_id and return_transaction_id", %{message: message} do
      assert {42, [header_bin, _chunk_bin]} =
               PPNet.encode_message(message, force_chunked: true, transaction_id: 42, return_transaction_id: true)

      assert %{messages: [%ChunkedMessageHeader{transaction_id: 42}], errors: []} = PPNet.parse(header_bin)
    end

    test "force_chunked: true works with chunk_indexes", %{message: message} do
      [_header | [chunk]] = PPNet.encode_message(message, force_chunked: true, transaction_id: 42)

      assert PPNet.encode_message(message, force_chunked: true, transaction_id: 42, chunk_indexes: [0]) == [chunk]
    end

    test "encode_message_stream/2 also honors force_chunked", %{message: message} do
      frames =
        message
        |> PPNet.encode_message_stream(force_chunked: true)
        |> Enum.to_list()

      assert [_header_bin, _chunk_bin] = frames
    end

    test "force_chunked: false keeps the single frame", %{message: message} do
      assert PPNet.encode_message(message, force_chunked: false) == PPNet.encode_message(message)
    end
  end

  describe "encode_message/2 option validation" do
    setup do
      {:ok,
       message: %SingleCounter{kind: "a", value: 1, pulses: 0, duration_ms: 10, datetime: ~U[2026-03-27 16:25:12Z]}}
    end

    for {name, opts} <- [
          {"a negative limit", [limit: -1]},
          {"a non-integer limit", [limit: "254"]},
          {"a negative transaction_id", [transaction_id: -1]},
          {"a transaction_id that does not fit in 4 bytes", [transaction_id: 4_294_967_296]},
          {"a non-boolean return_transaction_id", [return_transaction_id: "yes"]},
          {"a non-boolean force_chunked", [force_chunked: 1]},
          {"a non-boolean return_header", [return_header: :header]},
          {"chunk_indexes that is not a list", [chunk_indexes: 3]},
          {"a negative chunk index", [chunk_indexes: [-1]]},
          {"a non-integer chunk index", [chunk_indexes: ["1"]]},
          {"an unknown option", [chunk_indxes: [1]]}
        ] do
      @tag opts: opts
      test "encode_message/2 rejects #{name}, even for a single-frame message", %{message: message, opts: opts} do
        assert_raise NimbleOptions.ValidationError, fn -> PPNet.encode_message(message, opts) end
      end

      @tag opts: opts
      test "encode_message_stream/2 rejects #{name}", %{message: message, opts: opts} do
        assert_raise NimbleOptions.ValidationError, fn -> PPNet.encode_message_stream(message, opts) end
      end
    end

    test "transaction_id accepts the whole 4-byte range", %{message: message} do
      for transaction_id <- [0, 4_294_967_295] do
        assert {^transaction_id, [_header, _chunk]} =
                 PPNet.encode_message(message,
                   force_chunked: true,
                   transaction_id: transaction_id,
                   return_transaction_id: true
                 )
      end
    end

    test "an out-of-range limit is clamped instead of rejected", %{message: message} do
      assert PPNet.encode_message(message, limit: 9999) == PPNet.encode_message(message, limit: 254)
      assert PPNet.encode_message(message, limit: 0) == PPNet.encode_message(message, limit: 22)
    end
  end

  describe "encode PPNet.Message.ConfigData" do
    for kind <- Map.keys(@config_data_by_kind),
        format <- [:json, :msgpack],
        compression <- [:none, :brotli] do
      @tag kind: kind, format: format, compression: compression
      test "#{kind} round-trips with format: #{format}, compression: #{compression}",
           %{kind: kind, format: format, compression: compression} do
        message = %ConfigData{
          kind: kind,
          request_id: System.unique_integer([:positive]),
          format: format,
          compression: compression,
          request_payload: @config_data_by_kind[kind],
          datetime: ~U[2026-03-27 16:25:12Z]
        }

        encoded = PPNet.encode_message(message)
        assert is_binary(encoded), "expected a single frame, got: #{inspect(encoded)}"

        assert %{messages: [decoded], errors: []} = PPNet.parse(encoded)
        assert decoded == message
      end
    end

    for kind <- Map.keys(@invalid_config_data_by_kind) do
      @tag kind: kind
      test "#{kind} rejects an invalid request_payload", %{kind: kind} do
        message = %ConfigData{
          kind: kind,
          request_id: System.unique_integer([:positive]),
          format: :json,
          compression: :none,
          request_payload: @invalid_config_data_by_kind[kind],
          datetime: ~U[2026-03-27 16:25:12Z]
        }

        assert {:error, %PPNet.PackError{}} = ConfigData.pack(message)
      end
    end

    test "message too large is split into chunks" do
      schema =
        "test/support/static/config.schema.json"
        |> File.read!()
        |> Jason.decode!()

      message = %ConfigData{
        kind: :schema,
        request_id: System.unique_integer([:positive]),
        format: :json,
        compression: :none,
        request_payload: schema,
        datetime: ~U[2026-03-27 16:25:12Z]
      }

      [encoded_header | encoded_chunks] = PPNet.encode_message(message)

      assert %{messages: [decoded_header | decoded_chunks], errors: []} =
               [encoded_header | encoded_chunks]
               |> Enum.join()
               |> PPNet.parse()

      assert decoded_header.message_module == ConfigData
      assert decoded_header.total_chunks == length(decoded_chunks)

      assert Enum.all?(decoded_chunks, fn decoded_chunk ->
               decoded_chunk.transaction_id == decoded_header.transaction_id
             end)

      assert PPNet.chunked_to_message([decoded_header | decoded_chunks]) == {:ok, message}
    end

    test "full_report too large is split into chunks" do
      message = %ConfigData{
        kind: :full_report,
        request_id: System.unique_integer([:positive]),
        format: :json,
        compression: :none,
        request_payload: @full_config,
        datetime: ~U[2026-03-27 16:25:12Z]
      }

      [encoded_header | encoded_chunks] = PPNet.encode_message(message)

      assert %{messages: [decoded_header | decoded_chunks], errors: []} =
               [encoded_header | encoded_chunks]
               |> Enum.join()
               |> PPNet.parse()

      assert decoded_header.message_module == ConfigData
      assert decoded_header.total_chunks == length(decoded_chunks)

      assert Enum.all?(decoded_chunks, fn decoded_chunk ->
               decoded_chunk.transaction_id == decoded_header.transaction_id
             end)

      assert PPNet.chunked_to_message([decoded_header | decoded_chunks]) == {:ok, message}
    end

    test "pack/1 with invalid struct returns error" do
      # :unknown is not a valid kind
      assert {:error, %PPNet.PackError{reason: :invalid_struct}} =
               ConfigData.pack(%ConfigData{
                 kind: :unknown,
                 request_id: System.unique_integer([:positive]),
                 format: :json,
                 compression: :none,
                 request_payload: nil,
                 datetime: DateTime.utc_now()
               })
    end
  end

  describe "encode PPNet.Message.ConfigAck" do
    test "encode/1 with valid data" do
      message = %ConfigAck{request_id: 1, status: :ok, datetime: ~U[2026-03-27 16:25:12Z]}

      assert PPNet.encode_message(message) ==
               <<0x02, 0x0A, 0x01, 0x01, 0x02, 0x01, 0x0D, 0x69, 0xC6, 0xAF, 0x68, 0x5E, 0x59, 0x38, 0x8F, 0x73, 0x15,
                 0xD5, 0x60, 0x00>>
    end

    for status <- [:ok, :invalid_patch, :conflict, :decode_error, :unknown] do
      @tag status: status
      test "#{status} round-trips", %{status: status} do
        message = %ConfigAck{
          request_id: System.unique_integer([:positive]),
          status: status,
          datetime: ~U[2026-03-27 16:25:12Z]
        }

        encoded = PPNet.encode_message(message)
        assert byte_size(encoded) == 20

        assert %{messages: [decoded], errors: []} = PPNet.parse(encoded)
        assert decoded == message
      end
    end

    test "pack/1 with invalid struct returns error" do
      # negative request_id violates guard
      assert {:error, %PPNet.PackError{reason: :invalid_struct}} =
               ConfigAck.pack(%ConfigAck{request_id: -1, status: :ok, datetime: DateTime.utc_now()})

      # :bogus is not a valid status
      assert {:error, %PPNet.PackError{reason: :invalid_struct}} =
               ConfigAck.pack(%ConfigAck{request_id: 1, status: :bogus, datetime: DateTime.utc_now()})
    end
  end

  describe "encode PPNet.Message.ChunkedMessageAck" do
    test "encode/1 with valid data" do
      message = %ChunkedMessageAck{
        transaction_id: 42,
        status: :ok,
        missing_chunks: [],
        datetime: ~U[2026-03-27 16:25:12Z]
      }

      assert PPNet.encode_message(message) ==
               <<0x02, 0x08, 0x01, 0x01, 0x02, 0x2A, 0x01, 0x0D, 0x69, 0xC6, 0xAF, 0x68, 0x60, 0x0D, 0x7B, 0x91, 0x3D,
                 0x47, 0xC6, 0x71, 0x00>>
    end

    test "missing_chunks is delta+varint encoded" do
      # [3, 5, 130, 1000] -> deltas [3, 2, 125, 870]; 870 needs two varint bytes (0xE6, 0x06)
      message = %ChunkedMessageAck{
        transaction_id: 42,
        status: :incomplete,
        missing_chunks: [3, 5, 130, 1000],
        datetime: ~U[2026-03-27 16:25:12Z]
      }

      assert PPNet.encode_message(message) ==
               <<0x02, 0x08, 0x01, 0x01, 0x15, 0x2A, 0x01, 0x05, 0x03, 0x02, 0x7D, 0xE6, 0x06, 0x69, 0xC6, 0xAF, 0x68,
                 0x01, 0x8B, 0x6A, 0xD9, 0x71, 0x5C, 0xDC, 0x1A, 0x00>>
    end

    for {status, missing_chunks} <- [
          ok: [],
          incomplete: [3],
          incomplete: [3, 5, 130, 1000],
          incomplete: [200],
          missing_header: []
        ] do
      @tag status: status, missing_chunks: missing_chunks
      test "#{status} with missing_chunks #{inspect(missing_chunks)} round-trips",
           %{status: status, missing_chunks: missing_chunks} do
        message = %ChunkedMessageAck{
          transaction_id: System.unique_integer([:positive]),
          status: status,
          missing_chunks: missing_chunks,
          datetime: ~U[2026-03-27 16:25:12Z]
        }

        encoded = PPNet.encode_message(message)
        assert is_binary(encoded), "expected a single frame, got: #{inspect(encoded)}"

        assert %{messages: [decoded], errors: []} = PPNet.parse(encoded)
        assert decoded == message
      end
    end

    test "missing_chunks is sorted before encoding" do
      unsorted = %ChunkedMessageAck{
        transaction_id: 42,
        status: :incomplete,
        missing_chunks: [1000, 3, 130, 5],
        datetime: ~U[2026-03-27 16:25:12Z]
      }

      assert PPNet.encode_message(unsorted) ==
               PPNet.encode_message(%{unsorted | missing_chunks: [3, 5, 130, 1000]})
    end

    # The budget is in encoded bytes, not entries: 254 limit - 11 frame overhead - 10 fixed fields = 233.
    # Consecutive indexes have a delta of 1, one varint byte each, so 233 of them fill it exactly.
    test "pack/2 accepts as many missing_chunks as fit in the byte budget, and the frame stays within the limit" do
      message = %ChunkedMessageAck{
        transaction_id: 42,
        status: :incomplete,
        missing_chunks: Enum.to_list(0..232),
        datetime: ~U[2026-03-27 16:25:12Z]
      }

      assert is_binary(ChunkedMessageAck.pack(message, 254))

      frame = PPNet.encode_message(message)
      assert is_binary(frame)
      assert byte_size(frame) <= 254
      assert %{messages: [^message], errors: []} = PPNet.parse(frame)
    end

    test "pack/2 rejects missing_chunks whose encoded size exceeds the byte budget" do
      message = %ChunkedMessageAck{
        transaction_id: 42,
        status: :incomplete,
        missing_chunks: Enum.to_list(0..233),
        datetime: ~U[2026-03-27 16:25:12Z]
      }

      assert {:error,
              %PPNet.PackError{
                reason: :too_many_missing_chunks,
                data: %{count: 234, size: 234, max_size: 233, limit: 254}
              }} = ChunkedMessageAck.pack(message, 254)
    end

    test "pack/2 counts 3 bytes for gaps of 16384 or more, so 116 widely spaced entries do not fit" do
      # chunk_index is 16 bits: three gaps of 16384 cost 3 bytes each, the other 113 entries cost 2,
      # for 235 bytes. Counting 2 bytes per entry (116 * 2 = 232) would let this through and the
      # frame would exceed the limit.
      missing_chunks = [16_384, 32_768, 49_152] ++ Enum.map(1..113, &(49_152 + &1 * 128))

      message = %ChunkedMessageAck{
        transaction_id: 42,
        status: :incomplete,
        missing_chunks: missing_chunks,
        datetime: ~U[2026-03-27 16:25:12Z]
      }

      assert length(missing_chunks) == 116

      assert {:error,
              %PPNet.PackError{
                reason: :too_many_missing_chunks,
                data: %{count: 116, size: 235, max_size: 233, limit: 254}
              }} = ChunkedMessageAck.pack(message, 254)
    end

    test "pack/1 assumes the minimum limit, a budget of 1 encoded byte" do
      message = %ChunkedMessageAck{
        transaction_id: 42,
        status: :incomplete,
        missing_chunks: [1],
        datetime: ~U[2026-03-27 16:25:12Z]
      }

      assert is_binary(ChunkedMessageAck.pack(message))

      assert {:error, %PPNet.PackError{reason: :too_many_missing_chunks, data: %{size: 2, max_size: 1, limit: nil}}} =
               ChunkedMessageAck.pack(%{message | missing_chunks: [1, 2]})
    end

    test "pack/1 with invalid struct returns error" do
      # negative transaction_id violates guard
      assert {:error, %PPNet.PackError{reason: :invalid_struct}} =
               ChunkedMessageAck.pack(%ChunkedMessageAck{
                 transaction_id: -1,
                 status: :ok,
                 datetime: DateTime.utc_now()
               })

      # :bogus is not a valid status
      assert {:error, %PPNet.PackError{reason: :invalid_struct}} =
               ChunkedMessageAck.pack(%ChunkedMessageAck{
                 transaction_id: 1,
                 status: :bogus,
                 datetime: DateTime.utc_now()
               })

      # missing_chunks must be a list
      assert {:error, %PPNet.PackError{reason: :invalid_struct}} =
               ChunkedMessageAck.pack(%ChunkedMessageAck{
                 transaction_id: 1,
                 status: :incomplete,
                 missing_chunks: 3,
                 datetime: DateTime.utc_now()
               })
    end
  end

  describe "encode PPNet.Message.ChunkedMessageBody" do
    test "pack/1 with invalid struct returns error" do
      # negative transaction_id violates guard
      assert {:error, %PPNet.PackError{reason: :invalid_struct}} =
               ChunkedMessageBody.pack(%ChunkedMessageBody{
                 transaction_id: -1,
                 datetime: DateTime.utc_now(),
                 chunk_index: 0,
                 chunk_size: 5,
                 chunk_data: "hello"
               })

      # chunk_size declared as 100 but chunk_data is only 2 bytes — triggers rescue
      assert {:error, %PPNet.PackError{}} =
               ChunkedMessageBody.pack(%ChunkedMessageBody{
                 transaction_id: 0,
                 datetime: DateTime.utc_now(),
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

      assert byte_size(PPNet.encode_message(message)) == 93
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

      encoded = PPNet.encode_message(message)
      assert is_binary(encoded)
      assert byte_size(encoded) == 229
    end
  end
end
