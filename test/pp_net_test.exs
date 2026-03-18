# credo:disable-for-this-file Credo.Check.Design.DuplicatedCode
defmodule PPNetTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias PPNet.Message.ChunkedMessageBody
  alias PPNet.Message.ChunkedMessageHeader
  alias PPNet.Message.Event
  alias PPNet.Message.Hello
  alias PPNet.Message.Image
  alias PPNet.Message.Ping
  alias PPNet.Message.SingleCounter

  require Logger

  doctest PPNet

  defp corrupt_bytes(payload, positions) do
    payload
    |> :binary.bin_to_list()
    |> Enum.with_index()
    |> Enum.map(fn {byte, idx} ->
      if idx in positions do
        Bitwise.bxor(byte, 0xFF)
      else
        byte
      end
    end)
    |> :binary.list_to_bin()
  end

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

    test "parse/1 with valid binary data when the payload has 1 corrupted byte." do
      payload =
        <<0x29, 0x01, 0x96, 0xAA, 0x54, 0x65, 0x73, 0x74, 0x52, 0x75, 0x6E, 0x6E, 0x65, 0x72, 0xA6, 0x54, 0x65, 0x73,
          0x74, 0x65, 0x72, 0xCD, 0x12, 0x34, 0xCD, 0x43, 0x21, 0xCE, 0x05, 0x35, 0x34, 0x56, 0x01, 0x8F, 0xA5, 0x77,
          0xCC, 0xD7, 0x9B, 0x4C, 0xF4, 0x00>>

      corrupted = corrupt_bytes(payload, [3])
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

      assert log =~ "[info] Reed-Solomon corrected 1 errors in message of type Elixir.PPNet.Message.Hello"
    end

    test "parse/1 with valid binary data when the payload has 2 corrupted byte." do
      payload =
        <<0x29, 0x01, 0x96, 0xAA, 0x54, 0x65, 0x73, 0x74, 0x52, 0x75, 0x6E, 0x6E, 0x65, 0x72, 0xA6, 0x54, 0x65, 0x73,
          0x74, 0x65, 0x72, 0xCD, 0x12, 0x34, 0xCD, 0x43, 0x21, 0xCE, 0x05, 0x35, 0x34, 0x56, 0x01, 0x8F, 0xA5, 0x77,
          0xCC, 0xD7, 0x9B, 0x4C, 0xF4, 0x00>>

      corrupted = corrupt_bytes(payload, [3, 10])
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

      assert log =~ "[info] Reed-Solomon corrected 2 errors in message of type Elixir.PPNet.Message.Hello"
    end

    test "parse/1 with valid binary data when the payload has 3 corrupted byte." do
      payload =
        <<0x29, 0x01, 0x96, 0xAA, 0x54, 0x65, 0x73, 0x74, 0x52, 0x75, 0x6E, 0x6E, 0x65, 0x72, 0xA6, 0x54, 0x65, 0x73,
          0x74, 0x65, 0x72, 0xCD, 0x12, 0x34, 0xCD, 0x43, 0x21, 0xCE, 0x05, 0x35, 0x34, 0x56, 0x01, 0x8F, 0xA5, 0x77,
          0xCC, 0xD7, 0x9B, 0x4C, 0xF4, 0x00>>

      corrupted = corrupt_bytes(payload, [3, 10, 12])
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

      assert log =~ "[info] Reed-Solomon corrected 3 errors in message of type Elixir.PPNet.Message.Hello"
    end

    test "parse/1 with valid binary data when the payload has 4 corrupted byte." do
      payload =
        <<0x29, 0x01, 0x96, 0xAA, 0x54, 0x65, 0x73, 0x74, 0x52, 0x75, 0x6E, 0x6E, 0x65, 0x72, 0xA6, 0x54, 0x65, 0x73,
          0x74, 0x65, 0x72, 0xCD, 0x12, 0x34, 0xCD, 0x43, 0x21, 0xCE, 0x05, 0x35, 0x34, 0x56, 0x01, 0x8F, 0xA5, 0x77,
          0xCC, 0xD7, 0x9B, 0x4C, 0xF4, 0x00>>

      corrupted = corrupt_bytes(payload, [3, 10, 12, 23])
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

      assert log =~ "[info] Reed-Solomon corrected 4 errors in message of type Elixir.PPNet.Message.Hello"
    end

    test "parse/1 fail to correct corrupted bytes when exceeds 4 errors" do
      payload =
        <<0x29, 0x01, 0x96, 0xAA, 0x54, 0x65, 0x73, 0x74, 0x52, 0x75, 0x6E, 0x6E, 0x65, 0x72, 0xA6, 0x54, 0x65, 0x73,
          0x74, 0x65, 0x72, 0xCD, 0x12, 0x34, 0xCD, 0x43, 0x21, 0xCE, 0x05, 0x35, 0x34, 0x56, 0x01, 0x8F, 0xA5, 0x77,
          0xCC, 0xD7, 0x9B, 0x4C, 0xF4, 0x00>>

      corrupted = corrupt_bytes(payload, [3, 10, 12, 23, 40])

      assert %{
               errors: [
                 %PPNet.ParseError{
                   data: %{
                     payload: _payload
                   },
                   message: "Failed to parse message",
                   reason: {:reed_solomon, "decode_failed"}
                 }
               ],
               messages: []
             } = PPNet.parse(corrupted)
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

    test "parse/1 with invalid list returns error" do
      # 5 elements instead of 6 (missing ppnet_version)
      assert {:error, %PPNet.ParseError{reason: :unknown_format}} =
               Hello.parse(["UniqueId", "BoardId", 1, 1, 1])

      # version not an integer
      assert {:error, %PPNet.ParseError{reason: :unknown_format}} =
               Hello.parse(["UniqueId", "BoardId", "v1.0", 1, 1, 1])
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
                 ppnet_version: 1
               })

      # unique_id not a binary
      assert {:error, %PPNet.PackError{reason: :invalid_struct}} =
               Hello.pack(%Hello{
                 unique_id: 12_345,
                 board_identifier: "Tester",
                 version: 1,
                 board_version: 17_185,
                 boot_id: 87_372_886,
                 ppnet_version: 1
               })
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

    test "parse/1 with invalid list returns error" do
      # kind must be a binary string, not an integer
      assert {:error, %PPNet.ParseError{reason: :unknown_format}} =
               SingleCounter.parse([123, 42, 0, 1500])

      # pulses must be integer, not string
      assert {:error, %PPNet.ParseError{reason: :unknown_format}} =
               SingleCounter.parse(["bar", 42, "many", 1500])
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

    test "pack/1 with invalid struct returns error" do
      # kind must be a binary string
      assert {:error, %PPNet.PackError{reason: :invalid_struct}} =
               SingleCounter.pack(%SingleCounter{kind: 123, value: 42, pulses: 0, duration_ms: 1500})

      # duration_ms must be an integer
      assert {:error, %PPNet.PackError{reason: :invalid_struct}} =
               SingleCounter.pack(%SingleCounter{kind: "bar", value: 42, pulses: 0, duration_ms: "1500ms"})
    end

    test "encode_message/2 with limit above maximum clamps to 254" do
      message = %SingleCounter{kind: "a", value: 0, pulses: 0, duration_ms: 0}
      assert PPNet.encode_message(message, limit: 9999) == PPNet.encode_message(message)
    end

    test "encode_message/2 with limit below minimum clamps to 17" do
      message = %SingleCounter{kind: "a", value: 0, pulses: 0, duration_ms: 0}
      assert PPNet.encode_message(message, limit: 5) == PPNet.encode_message(message, limit: 17)
    end
  end

  describe "backward compatibility: decode PPNet.Message.Ping (v0.1.1)" do
    test "parse/1 with valid binary data" do
      payload =
        <<0x06, 0x03, 0x99, 0xCB, 0x40, 0x39, 0x01, 0x01, 0x01, 0x01, 0x01, 0x02, 0xCF, 0x01, 0x06, 0x01, 0x25, 0xE7,
          0x2E, 0x78, 0x1A, 0x93, 0xCB, 0x40, 0x44, 0x5B, 0x3D, 0x6F, 0x56, 0xFA, 0xE4, 0xCB, 0xC0, 0x52, 0x80, 0x62,
          0x81, 0x9A, 0x49, 0x6D, 0xCD, 0x27, 0x10, 0xCB, 0x3F, 0xE0, 0x01, 0x01, 0x01, 0x01, 0x01, 0x05, 0x32, 0x64,
          0x9A, 0xA7, 0x4D, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E, 0xD6, 0xA7, 0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xC9, 0xA7,
          0xDC, 0xFE, 0x01, 0x23, 0x45, 0x67, 0xBA, 0xA7, 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xBF, 0xA7, 0xA1, 0xB2,
          0xC3, 0xD4, 0xE5, 0xF6, 0xB0, 0xA7, 0x9A, 0xBC, 0xDE, 0xF0, 0x12, 0x34, 0xC4, 0xA7, 0xFE, 0xDC, 0xBA, 0x98,
          0x76, 0x54, 0xB5, 0xA7, 0x02, 0x04, 0x06, 0x08, 0x0A, 0x0C, 0xCF, 0xA7, 0xF0, 0xE1, 0xD2, 0xC3, 0xB4, 0xA5,
          0xC6, 0xA7, 0x55, 0x44, 0x33, 0x22, 0x11, 0x1F, 0xC3, 0x92, 0xCD, 0x03, 0xE8, 0xCD, 0x01, 0xF4, 0x82, 0xA3,
          0x66, 0x6F, 0x6F, 0xA3, 0x62, 0x61, 0x72, 0xA3, 0x62, 0x61, 0x7A, 0x7B, 0x1A, 0x5A, 0x70, 0x6C, 0x5C, 0xD5,
          0x5E, 0xCE, 0x00>>

      assert %{
               messages: [
                 %Ping{
                   temperature: 25.0,
                   uptime_ms: 1_262_304_000_000,
                   cpu: 0.5,
                   location: %{lat: 40.712812345, lon: -74.006012345, accuracy: 10_000},
                   storage: %{total: 1000, used: 500},
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
                   extra: %{"baz" => 123, "foo" => "bar"}
                 }
               ],
               errors: []
             } = PPNet.parse(payload)
    end

    test "parse/1 with valid binary data and extra is present" do
      payload =
        <<0x06, 0x03, 0x99, 0xCB, 0x40, 0x39, 0x01, 0x01, 0x01, 0x01, 0x01, 0x1D, 0xCD, 0x03, 0xE8, 0x93, 0xCB, 0x40,
          0x44, 0x5B, 0x3D, 0x6F, 0x56, 0xFA, 0xE4, 0xCB, 0xC0, 0x52, 0x80, 0x62, 0x81, 0x9A, 0x49, 0x6D, 0xCD, 0x27,
          0x10, 0xCB, 0x3F, 0xE0, 0x01, 0x01, 0x01, 0x01, 0x01, 0x21, 0x32, 0x64, 0x90, 0x92, 0xCD, 0x03, 0xE8, 0xCD,
          0x01, 0xF4, 0x82, 0xA3, 0x62, 0x61, 0x7A, 0x7B, 0xA3, 0x66, 0x6F, 0x6F, 0xA3, 0x62, 0x61, 0x72, 0xC5, 0x02,
          0x06, 0x8F, 0x44, 0x8A, 0x7B, 0xFC, 0x00>>

      assert %{
               messages: [
                 %Ping{
                   cpu: 0.5,
                   location: %{accuracy: 10_000, lat: 40.712812345, lon: -74.006012345},
                   storage: %{total: 1000, used: 500},
                   temperature: 25.0,
                   tpu_memory_percent: 50,
                   tpu_ping_ms: 100,
                   uptime_ms: 1000,
                   wifi: [],
                   extra: %{"baz" => 123, "foo" => "bar"}
                 }
               ],
               errors: []
             } = PPNet.parse(payload)
    end
  end

  describe "decode PPNet.Message.Ping" do
    test "parse/1 with valid binary data" do
      payload =
        <<0x04, 0x03, 0x9A, 0xDC, 0x19, 0x10, 0x53, 0xCC, 0x88, 0x72, 0x4C, 0x45, 0x7E, 0x43, 0x32, 0xCC, 0xA9, 0xCC,
          0x8C, 0xCC, 0xE6, 0x7B, 0x20, 0x53, 0x66, 0x2C, 0xCB, 0x40, 0x39, 0x01, 0x01, 0x01, 0x01, 0x01, 0x02, 0xCF,
          0x01, 0x06, 0x01, 0x25, 0xE7, 0x2E, 0x78, 0x1A, 0x93, 0xCB, 0x40, 0x44, 0x5B, 0x3D, 0x6F, 0x56, 0xFA, 0xE4,
          0xCB, 0xC0, 0x52, 0x80, 0x62, 0x81, 0x9A, 0x49, 0x6D, 0xCD, 0x27, 0x10, 0xCB, 0x3F, 0xE0, 0x01, 0x01, 0x01,
          0x01, 0x01, 0x05, 0x32, 0x64, 0x9A, 0xA7, 0x4D, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E, 0xD6, 0xA7, 0x01, 0x23, 0x45,
          0x67, 0x89, 0xAB, 0xC9, 0xA7, 0xDC, 0xFE, 0x01, 0x23, 0x45, 0x67, 0xBA, 0xA7, 0x12, 0x34, 0x56, 0x78, 0x9A,
          0xBC, 0xBF, 0xA7, 0xA1, 0xB2, 0xC3, 0xD4, 0xE5, 0xF6, 0xB0, 0xA7, 0x9A, 0xBC, 0xDE, 0xF0, 0x12, 0x34, 0xC4,
          0xA7, 0xFE, 0xDC, 0xBA, 0x98, 0x76, 0x54, 0xB5, 0xA7, 0x02, 0x04, 0x06, 0x08, 0x0A, 0x0C, 0xCF, 0xA7, 0xF0,
          0xE1, 0xD2, 0xC3, 0xB4, 0xA5, 0xC6, 0xA7, 0x55, 0x44, 0x33, 0x22, 0x11, 0x1F, 0xC3, 0x92, 0xCD, 0x03, 0xE8,
          0xCD, 0x01, 0xF4, 0x82, 0xA3, 0x66, 0x6F, 0x6F, 0xA3, 0x62, 0x61, 0x72, 0xA3, 0x62, 0x61, 0x7A, 0x7B, 0x14,
          0xD0, 0x97, 0x92, 0x1B, 0xF1, 0x77, 0xF8, 0x00>>

      assert %{
               messages: [
                 %Ping{
                   session_id: "5388724c-457e-4332-a98c-e67b2053662c",
                   temperature: 25.0,
                   uptime_ms: 1_262_304_000_000,
                   cpu: 0.5,
                   location: %{lat: 40.712812345, lon: -74.006012345, accuracy: 10_000},
                   storage: %{total: 1000, used: 500},
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
                   extra: %{"baz" => 123, "foo" => "bar"}
                 }
               ],
               errors: []
             } = PPNet.parse(payload)
    end

    test "parse/1 with valid binary data and extra is present" do
      payload =
        <<0x04, 0x03, 0x9A, 0xDC, 0x19, 0x10, 0x53, 0xCC, 0x88, 0x72, 0x4C, 0x45, 0x7E, 0x43, 0x32, 0xCC, 0xA9, 0xCC,
          0x8C, 0xCC, 0xE6, 0x7B, 0x20, 0x53, 0x66, 0x2C, 0xCB, 0x40, 0x39, 0x01, 0x01, 0x01, 0x01, 0x01, 0x1D, 0xCD,
          0x03, 0xE8, 0x93, 0xCB, 0x40, 0x44, 0x5B, 0x3D, 0x6F, 0x56, 0xFA, 0xE4, 0xCB, 0xC0, 0x52, 0x80, 0x62, 0x81,
          0x9A, 0x49, 0x6D, 0xCD, 0x27, 0x10, 0xCB, 0x3F, 0xE0, 0x01, 0x01, 0x01, 0x01, 0x01, 0x21, 0x32, 0x64, 0x90,
          0x92, 0xCD, 0x03, 0xE8, 0xCD, 0x01, 0xF4, 0x82, 0xA3, 0x66, 0x6F, 0x6F, 0xA3, 0x62, 0x61, 0x72, 0xA3, 0x62,
          0x61, 0x7A, 0x7B, 0x99, 0x6C, 0xD8, 0xE6, 0x16, 0xB8, 0x18, 0x9B, 0x00>>

      assert %{
               messages: [
                 %Ping{
                   session_id: "5388724c-457e-4332-a98c-e67b2053662c",
                   cpu: 0.5,
                   location: %{accuracy: 10_000, lat: 40.712812345, lon: -74.006012345},
                   storage: %{total: 1000, used: 500},
                   temperature: 25.0,
                   tpu_memory_percent: 50,
                   tpu_ping_ms: 100,
                   uptime_ms: 1000,
                   wifi: [],
                   extra: %{"baz" => 123, "foo" => "bar"}
                 }
               ],
               errors: []
             } = PPNet.parse(payload)
    end

    test "parse/1 with invalid list returns error" do
      # temperature must be a float, not an integer (legacy 9-element format)
      assert {:error, %PPNet.ParseError{reason: :unknown_format}} =
               Ping.parse([25, 1000, [40.0, -74.0, 100], 0.5, 50, 100, [], [1000, 500], %{}])

      # extra must be a map, not a list (current 10-element format)
      assert {:error, %PPNet.ParseError{reason: :unknown_format}} =
               Ping.parse([[], 25.0, 1000, [40.0, -74.0, 100], 0.5, 50, 100, [], [1000, 500], ["not", "a", "map"]])
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
          storage: %{total: 1000, used: 500}
        }

      assert PPNet.encode_message(message) ==
               <<0x04, 0x03, 0x9A, 0xDC, 0x19, 0x10, 0x53, 0xCC, 0x88, 0x72, 0x4C, 0x45, 0x7E, 0x43, 0x32, 0xCC, 0xA9,
                 0xCC, 0x8C, 0xCC, 0xE6, 0x7B, 0x20, 0x53, 0x66, 0x2C, 0xCB, 0x40, 0x39, 0x01, 0x01, 0x01, 0x01, 0x01,
                 0x02, 0xCE, 0x1D, 0x01, 0x86, 0xA0, 0x93, 0xCB, 0x40, 0x44, 0x5B, 0x3D, 0x6F, 0x56, 0xFA, 0xE4, 0xCB,
                 0xC0, 0x52, 0x80, 0x62, 0x81, 0x9A, 0x49, 0x6D, 0xCD, 0x27, 0x10, 0xCB, 0x3F, 0xE0, 0x01, 0x01, 0x01,
                 0x01, 0x01, 0x05, 0x32, 0x64, 0x92, 0xA7, 0x1F, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E, 0xD6, 0xA7, 0x01, 0x23,
                 0x45, 0x67, 0x89, 0xAB, 0xC9, 0x92, 0xCD, 0x03, 0xE8, 0xCD, 0x01, 0xF4, 0x80, 0xCB, 0xB1, 0xFA, 0x49,
                 0x1B, 0x9F, 0x24, 0xD5, 0x00>>
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
        storage: %{total: 1000, used: 500}
      }

      assert PPNet.encode_message(message) ==
               <<0x04, 0x03, 0x9A, 0xDC, 0x19, 0x10, 0x53, 0xCC, 0x88, 0x72, 0x4C, 0x45, 0x7E, 0x43, 0x32, 0xCC, 0xA9,
                 0xCC, 0x8C, 0xCC, 0xE6, 0x7B, 0x20, 0x53, 0x66, 0x2C, 0xCB, 0x40, 0x39, 0x01, 0x01, 0x01, 0x01, 0x01,
                 0x1D, 0xCD, 0x03, 0xE8, 0x93, 0xCB, 0x40, 0x44, 0x5B, 0x3D, 0x6F, 0x56, 0xFA, 0xE4, 0xCB, 0xC0, 0x52,
                 0x80, 0x62, 0x81, 0x9A, 0x49, 0x6D, 0xCD, 0x27, 0x10, 0xCB, 0x3F, 0xE0, 0x01, 0x01, 0x01, 0x01, 0x01,
                 0x21, 0x32, 0x64, 0x90, 0x92, 0xCD, 0x03, 0xE8, 0xCD, 0x01, 0xF4, 0x82, 0xA3, 0x62, 0x61, 0x7A, 0x7B,
                 0xA3, 0x66, 0x6F, 0x6F, 0xA3, 0x62, 0x61, 0x72, 0xE1, 0xFE, 0x14, 0xEA, 0xDF, 0xD7, 0x7B, 0x74, 0x00>>
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
                 storage: %{total: 1000, used: 500}
               })
    end
  end

  describe "decode PPNet.Message.Event" do
    test "parse/1 with valid binary data" do
      payload =
        <<0x1F, 0x04, 0x92, 0x01, 0x82, 0xA5, 0x76, 0x61, 0x6C, 0x75, 0x65, 0x64, 0xA9, 0x73, 0x65, 0x6E, 0x73, 0x6F,
          0x72, 0x5F, 0x69, 0x64, 0x01, 0x84, 0x7F, 0xF5, 0x46, 0x64, 0xA1, 0x40, 0x9E, 0x00>>

      assert %{
               messages: [
                 %Event{
                   data: %{"sensor_id" => 1, "value" => 100},
                   kind: :detection
                 }
               ],
               errors: []
             } = PPNet.parse(payload)
    end

    test "parse/1 with invalid list returns error" do
      # kind code 99 is not a valid event kind
      assert {:error, %PPNet.ParseError{reason: :unknown_format}} =
               Event.parse([99, %{"sensor_id" => 1}])

      # data must be a map, not a list
      assert {:error, %PPNet.ParseError{reason: :unknown_format}} =
               Event.parse([1, ["sensor_id", 1]])
    end
  end

  describe "encode PPNet.Message.Event" do
    test "encode/1 with valid data" do
      assert PPNet.encode_message(%Event{
               kind: :detection,
               data: %{sensor_id: 1, value: 100}
             }) ==
               <<0x1F, 0x04, 0x92, 0x01, 0x82, 0xA9, 0x73, 0x65, 0x6E, 0x73, 0x6F, 0x72, 0x5F, 0x69, 0x64, 0x01, 0xA5,
                 0x76, 0x61, 0x6C, 0x75, 0x65, 0x64, 0xDD, 0xB8, 0x4E, 0x7F, 0x7E, 0x8D, 0xA5, 0x51, 0x00>>
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
        data: data
      }

      assert PPNet.encode_message(event) ==
               <<0x0F, 0x04, 0x92, 0x01, 0x82, 0xA8, 0x69, 0x6D, 0x61, 0x67, 0x65, 0x5F, 0x69, 0x64, 0xDC, 0x2B, 0x10,
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
                 0x01, 0x08, 0xCB, 0x40, 0x55, 0x76, 0xDE, 0x52, 0x40, 0x01, 0x09, 0xD0, 0xA3, 0x0B, 0x86, 0xD2, 0x7F,
                 0x3E, 0xFE, 0x00>>
    end

    test "message too large is split into chunks" do
      message = %Event{
        kind: :detection,
        data: %{"sensor_id" => 1, "value" => String.duplicate("a", 100)}
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
               Event.pack(%Event{kind: :unknown_event, data: %{"sensor_id" => 1}})

      # data must be a map
      assert {:error, %PPNet.PackError{reason: :invalid_struct}} =
               Event.pack(%Event{kind: :detection, data: ["not", "a", "map"]})
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

  describe "decode image" do
    test "parse/1 with valid binary data" do
      payload = File.read!("test/support/static/image.webp")

      assert %{
               messages: [
                 %ChunkedMessageHeader{
                   message_module: Image,
                   transaction_id: transaction_id,
                   total_chunks: 150,
                   datetime: %DateTime{}
                 }
                 | chunks
               ],
               errors: []
             } =
               %Image{id: UUID.uuid4(), data: payload, format: :webp}
               |> PPNet.encode_message(limit: 200)
               |> Enum.join()
               |> PPNet.parse()

      assert Enum.all?(chunks, fn chunk ->
               %ChunkedMessageBody{
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

    test "parse/1 with short binary returns error" do
      # less than 17 bytes: can't match <<id::16, format_code::1, data::binary>>
      assert {:error, %PPNet.ParseError{reason: :unknown_format}} = Image.parse(<<1, 2, 3>>)
    end
  end

  describe "decode PPNet.Message.ChunkedMessageBody" do
    test "parse/1 with list input returns error" do
      # expects a binary, not a list
      assert {:error, %PPNet.ParseError{reason: :unknown_format}} =
               ChunkedMessageBody.parse([0, 0, 5, "hello"])
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

  describe "decode PPNet.Message.ChunkedMessageHeader" do
    test "parse/1 with list input returns error" do
      # expects an 11-byte binary, not a list
      assert {:error, %PPNet.ParseError{reason: :unknown_format}} =
               ChunkedMessageHeader.parse([1, 1234, 0, 1])
    end

    test "parse/1 decodes SingleCounter message module" do
      # exercises the to_message_type(@single_counter_type_code) clause
      message = %SingleCounter{
        kind: String.duplicate("x", 20),
        value: 0,
        pulses: 0,
        duration_ms: 0
      }

      [header_bin | _chunks] = PPNet.encode_message(message, limit: 30)

      assert %{
               messages: [%ChunkedMessageHeader{message_module: SingleCounter}],
               errors: []
             } = PPNet.parse(header_bin)
    end
  end

  describe "encode PPNet.Message.ChunkedMessageHeader" do
    test "pack/1 with invalid struct returns error" do
      # ChunkedMessageBody is not a valid message_module for chunked headers
      assert {:error, %PPNet.PackError{reason: :invalid_struct}} =
               ChunkedMessageHeader.pack(%ChunkedMessageHeader{
                 message_module: ChunkedMessageBody,
                 transaction_id: 0,
                 datetime: ~U[2024-01-01 00:00:00Z],
                 total_chunks: 1
               })

      # total_chunks must be an integer
      assert {:error, %PPNet.PackError{reason: :invalid_struct}} =
               ChunkedMessageHeader.pack(%ChunkedMessageHeader{
                 message_module: Hello,
                 transaction_id: 0,
                 datetime: ~U[2024-01-01 00:00:00Z],
                 total_chunks: "three"
               })
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

    test "chunked_to_message/1 error cases" do
      header = %ChunkedMessageHeader{
        message_module: Hello,
        transaction_id: 1234,
        datetime: ~U[2024-01-01 00:00:00Z],
        total_chunks: 1
      }

      # chunk_data is garbage — Hello.parse will fail on reassembled binary
      bad_data_chunk = %ChunkedMessageBody{
        transaction_id: 1234,
        chunk_index: 0,
        chunk_size: 3,
        chunk_data: <<0xFF, 0xFE, 0xFD>>
      }

      assert {:error, %PPNet.ParseError{}} =
               PPNet.chunked_to_message([header, bad_data_chunk])

      # total_chunks says 3 but only 1 chunk provided
      big_header = %ChunkedMessageHeader{
        message_module: Hello,
        transaction_id: 1234,
        datetime: ~U[2024-01-01 00:00:00Z],
        total_chunks: 3
      }

      assert {:error, %PPNet.ParseError{reason: :missing_chunks}} =
               PPNet.chunked_to_message([big_header, bad_data_chunk])
    end

    test "parse/1 with valid frame but semantically invalid message body returns error" do
      # type=1 (Hello) with valid msgpack but wrong structure (2 strings instead of 6 typed fields)
      raw = <<1::8>> <> Msgpax.pack!(["UniqueId", "BoardId"], iodata: false)
      {:ok, rs_encoded} = ReedSolomonEx.encode(raw, 8)
      payload = Cobs.encode!(rs_encoded) <> <<0x00>>

      assert %{messages: [], errors: [%PPNet.ParseError{}]} = PPNet.parse(payload)
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
          session_id: "5388724c-457e-4332-a98c-e67b2053662c",
          temperature: 25.0,
          uptime_ms: 1_262_304_000_000,
          location: %{lat: 40.712812345, lon: -74.006012345, accuracy: 10_000},
          cpu: 0.5,
          tpu_memory_percent: 50,
          tpu_ping_ms: 100,
          wifi: [
            %{mac: "00:1A:2B:3C:4D:5E", rssi: -42}
          ],
          storage: %{total: 1000, used: 500}
        })

      event =
        PPNet.encode_message(%Event{
          kind: :detection,
          data: %{"sensor_id" => 1, "value" => 100}
        })

      image = File.read!("test/support/static/image.webp")

      [image_header | image_chunks] =
        PPNet.encode_message(
          %Image{id: UUID.uuid4(), data: image, format: :webp},
          limit: 200
        )

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
               %ChunkedMessageHeader{
                 message_module: Image,
                 transaction_id: transaction_id,
                 total_chunks: total_chunks
               }
               | rest_1
             ] = messages

      assert [
               %Ping{
                 temperature: 25.0,
                 uptime_ms: 1_262_304_000_000,
                 location: %{lat: 40.712812345, lon: -74.006012345, accuracy: 10_000},
                 cpu: 0.5,
                 tpu_memory_percent: 50,
                 tpu_ping_ms: 100,
                 wifi: [
                   %{mac: "00:1A:2B:3C:4D:5E", rssi: -42}
                 ],
                 storage: %{total: 1000, used: 500}
               }
               | rest_2
             ] = rest_1

      {chunks, rest_3} = Enum.split(rest_2, total_chunks)

      assert Enum.all?(Enum.with_index(chunks), fn {chunk, index} ->
               assert %ChunkedMessageBody{
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
                 kind: :detection,
                 data: %{"sensor_id" => 1, "value" => 100}
               }
             ] = rest_5
    end
  end
end
