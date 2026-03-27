defmodule BackwardCompatibilityTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import PPNet.Test.Helper

  # alias PPNet.Message.ChunkedMessageBody
  # alias PPNet.Message.ChunkedMessageHeader
  # alias PPNet.Message.Event
  alias PPNet.Message.Hello
  # alias PPNet.Message.Image
  alias PPNet.Message.Ping
  alias PPNet.Message.SingleCounter

  require Logger

  describe "decode PPNet.Message.Hello (from v0.1.3)" do
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

    test "parse/1 with valid binary data when payload is a list" do
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

    test "parse/1 with valid binary data when payload is corrupted (payload from v0.1.3)" do
      payload =
        <<0x29, 0x01, 0x96, 0xAA, 0x54, 0x65, 0x73, 0x74, 0x52, 0x75, 0x6E, 0x6E, 0x65, 0x72, 0xA6, 0x54, 0x65, 0x73,
          0x74, 0x65, 0x72, 0xCD, 0x12, 0x34, 0xCD, 0x43, 0x21, 0xCE, 0x05, 0x35, 0x34, 0x56, 0x01, 0x8F, 0xA5, 0x77,
          0xCC, 0xD7, 0x9B, 0x4C, 0xF4, 0x00>>

      <<a::binary-size(3)-unit(8), _b::binary-size(1)-unit(8), rest::binary>> = payload
      corrupted = <<a::binary-size(3)-unit(8), 1::unsigned-integer-size(1)-unit(8), rest::binary>>
      {result, log} = with_log(fn -> PPNet.parse(corrupted) end)

      assert %{
               messages: [
                 %Hello{
                   version: 4660,
                   ppnet_version: 1,
                   boot_id: 87_372_886,
                   board_version: 17_185,
                   board_identifier: "Tester",
                   unique_id: "TestRunner",
                   datetime: nil
                 }
               ],
               errors: []
             } = result

      assert log =~ "Reed-Solomon corrected 1 errors in message of type #{Hello}"
    end

    test "parse/1 with valid binary data when the payload has 1 corrupted byte." do
      payload =
        <<0x29, 0x01, 0x96, 0xAA, 0x54, 0x65, 0x73, 0x74, 0x52, 0x75, 0x6E, 0x6E, 0x65, 0x72, 0xA6, 0x54, 0x65, 0x73,
          0x74, 0x65, 0x72, 0xCD, 0x12, 0x34, 0xCD, 0x43, 0x21, 0xCE, 0x05, 0x35, 0x34, 0x56, 0x01, 0x8F, 0xA5, 0x77,
          0xCC, 0xD7, 0x9B, 0x4C, 0xF4, 0x00>>

      corrupted = corrupt_bytes(payload, [3])
      {result, log} = with_log(fn -> PPNet.parse(corrupted) end)

      assert %{
               messages: [
                 %Hello{
                   version: 4660,
                   ppnet_version: 1,
                   boot_id: 87_372_886,
                   board_version: 17_185,
                   board_identifier: "Tester",
                   unique_id: "TestRunner",
                   datetime: nil
                 }
               ],
               errors: []
             } = result

      assert log =~ "[info] Reed-Solomon corrected 1 errors in message of type Elixir.PPNet.Message.Hello"
    end

    test "parse/1 with valid binary data when the payload has 2 corrupted byte." do
      payload =
        <<0x29, 0x01, 0x96, 0xAA, 0x54, 0x65, 0x73, 0x74, 0x52, 0x75, 0x6E, 0x6E, 0x65, 0x72, 0xA6, 0x54, 0x65, 0x73,
          0x74, 0x65, 0x72, 0xCD, 0x12, 0x34, 0xCD, 0x43, 0x21, 0xCE, 0x05, 0x35, 0x34, 0x56, 0x01, 0x8F, 0xA5, 0x77,
          0xCC, 0xD7, 0x9B, 0x4C, 0xF4, 0x00>>

      corrupted = corrupt_bytes(payload, [3, 10])
      {result, log} = with_log(fn -> PPNet.parse(corrupted) end)

      assert %{
               messages: [
                 %Hello{
                   version: 4660,
                   ppnet_version: 1,
                   boot_id: 87_372_886,
                   board_version: 17_185,
                   board_identifier: "Tester",
                   unique_id: "TestRunner",
                   datetime: nil
                 }
               ],
               errors: []
             } = result

      assert log =~ "[info] Reed-Solomon corrected 2 errors in message of type Elixir.PPNet.Message.Hello"
    end

    test "parse/1 with valid binary data when the payload has 3 corrupted byte." do
      payload =
        <<0x29, 0x01, 0x96, 0xAA, 0x54, 0x65, 0x73, 0x74, 0x52, 0x75, 0x6E, 0x6E, 0x65, 0x72, 0xA6, 0x54, 0x65, 0x73,
          0x74, 0x65, 0x72, 0xCD, 0x12, 0x34, 0xCD, 0x43, 0x21, 0xCE, 0x05, 0x35, 0x34, 0x56, 0x01, 0x8F, 0xA5, 0x77,
          0xCC, 0xD7, 0x9B, 0x4C, 0xF4, 0x00>>

      corrupted = corrupt_bytes(payload, [3, 10, 12])
      {result, log} = with_log(fn -> PPNet.parse(corrupted) end)

      assert %{
               messages: [
                 %Hello{
                   version: 4660,
                   ppnet_version: 1,
                   boot_id: 87_372_886,
                   board_version: 17_185,
                   board_identifier: "Tester",
                   unique_id: "TestRunner",
                   datetime: nil
                 }
               ],
               errors: []
             } = result

      assert log =~ "[info] Reed-Solomon corrected 3 errors in message of type Elixir.PPNet.Message.Hello"
    end

    test "parse/1 with valid binary data when the payload has 4 corrupted byte." do
      payload =
        <<0x29, 0x01, 0x96, 0xAA, 0x54, 0x65, 0x73, 0x74, 0x52, 0x75, 0x6E, 0x6E, 0x65, 0x72, 0xA6, 0x54, 0x65, 0x73,
          0x74, 0x65, 0x72, 0xCD, 0x12, 0x34, 0xCD, 0x43, 0x21, 0xCE, 0x05, 0x35, 0x34, 0x56, 0x01, 0x8F, 0xA5, 0x77,
          0xCC, 0xD7, 0x9B, 0x4C, 0xF4, 0x00>>

      corrupted = corrupt_bytes(payload, [3, 10, 12, 23])
      {result, log} = with_log(fn -> PPNet.parse(corrupted) end)

      assert %{
               messages: [
                 %Hello{
                   version: 4660,
                   ppnet_version: 1,
                   boot_id: 87_372_886,
                   board_version: 17_185,
                   board_identifier: "Tester",
                   unique_id: "TestRunner",
                   datetime: nil
                 }
               ],
               errors: []
             } = result

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

  describe "decode PPNet.Message.Ping (from v0.1.1)" do
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

  describe "decode PPNet.Message.SingleCounter (from v0.1.3)" do
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
                   kind: "bar",
                   datetime: nil
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
                     kind: "bar",
                     datetime: nil
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

  describe "decode PPNet.Message.Ping (from v0.1.3)" do
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
                   datetime: nil,
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
                   datetime: nil,
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
end
