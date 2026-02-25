defmodule PPNetTest do
  use ExUnit.Case, async: true

  alias PPNet.Message.Hello
  alias PPNet.Message.SingleCounter

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

      assert {
               :ok,
               %Hello{
                 board_identifier: "Tester",
                 board_version: 17_185,
                 boot_id: 87_372_886,
                 checksum: 3_658_615_887,
                 ppnet_version: 1,
                 unique_id: "TestRunner",
                 valid: true,
                 version: 4660
               }
             } = PPNet.parse(payload)
    end

    test "parse/1 with valid binary data when payload is a" do
      payload =
        :binary.bin_to_list(
          <<0x01, 0xDA, 0x12, 0x0C, 0x4F, 0x96, 0xAA, 0x54, 0x65, 0x73, 0x74, 0x52, 0x75, 0x6E,
            0x6E, 0x65, 0x72, 0xA6, 0x54, 0x65, 0x73, 0x74, 0x65, 0x72, 0xCD, 0x12, 0x34, 0xCD,
            0x43, 0x21, 0xCE, 0x05, 0x35, 0x34, 0x56, 0x01>>
        )

      assert {
               :ok,
               %Hello{
                 board_identifier: "Tester",
                 board_version: 17_185,
                 boot_id: 87_372_886,
                 checksum: 3_658_615_887,
                 ppnet_version: 1,
                 unique_id: "TestRunner",
                 valid: true,
                 version: 4660
               }
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

      assert {:error,
              %PPNet.ParseError{
                message: "Unable to decode message body for type Elixir.PPNet.Message.Hello",
                reason: %Msgpax.UnpackError{reason: :incomplete},
                data: <<1, 218, 18, 12, 79, 148, 160, 0>>
              }} =
               PPNet.parse(payload)
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

      assert {:ok,
              %SingleCounter{
                duration_ms: 1500,
                kind: "bar",
                pulses: 0,
                value: 42,
                checksum: 403_637_317,
                valid: true
              }} =
               PPNet.parse(payload)
    end

    test "parse/1 with valid binary data when payload is a list" do
      payload =
        :binary.bin_to_list(
          <<0x02, 0x18, 0x0F, 0x04, 0x45, 0x94, 0xA3, 0x62, 0x61, 0x72, 0x2A, 0x00, 0xCD, 0x05,
            0xDC>>
        )

      assert PPNet.parse(payload) ==
               {:ok,
                %SingleCounter{
                  duration_ms: 1500,
                  kind: "bar",
                  pulses: 0,
                  value: 42,
                  checksum: 403_637_317,
                  valid: true
                }}
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

      assert {:error,
              %PPNet.ParseError{
                message:
                  "Unable to decode message body for type Elixir.PPNet.Message.SingleCounter",
                reason: %Msgpax.UnpackError{reason: :incomplete},
                data: <<2, 24, 15, 4, 69, 148, 160, 0>>
              }} =
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

  describe "PPNet" do
    test "unknown message type" do
      payload = <<
        # message type
        0x03,
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

      assert {:error,
              %PPNet.ParseError{
                message: "Unknown message format",
                reason: :unknown_format,
                data: <<3, 24, 15, 4, 69, 148, 160, 0>>
              }} =
               PPNet.parse(payload)
    end
  end
end
