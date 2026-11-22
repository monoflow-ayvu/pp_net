defmodule PPNetHeatshrinkTest do
  use ExUnit.Case, async: true

  alias PPNet.Heatshrink

  @known_answer_input "hello world, how are hello world, you doing\n"
  @known_answer_encoded <<0xB4, 0x59, 0x6D, 0x96, 0xCB, 0x7C, 0x82, 0xEF, 0x6F, 0xB9, 0x5B, 0x2C, 0x92, 0xC9, 0x05,
                          0xA2, 0xDF, 0x77, 0x90, 0x58, 0x6E, 0x56, 0x50, 0x38, 0x85, 0x2E, 0xF3, 0x6F, 0xBA, 0xC8,
                          0x2C, 0x96, 0xFB, 0x4D, 0xBA, 0xCF, 0x0A>>

  test "matches the upstream 8/4 known-answer vector" do
    assert {:ok, @known_answer_encoded} = Heatshrink.encode(@known_answer_input)
    assert {:ok, @known_answer_input} = Heatshrink.decode(@known_answer_encoded)
  end

  test "round-trips empty and repetitive payloads" do
    repetitive = for i <- 0..8191, into: <<>>, do: <<rem(i * i * 109 + 17, 256)>>

    for payload <- [<<>>, repetitive] do
      assert {:ok, encoded} = Heatshrink.encode(payload)
      assert {:ok, decoded} = Heatshrink.decode(encoded)
      assert decoded == payload
    end
  end

  test "grows output for an incompressible payload and round-trips exactly" do
    payload = for i <- 0..255, into: <<>>, do: :crypto.hash(:sha256, <<i::unsigned-32>>)

    assert {:ok, encoded} = Heatshrink.encode(payload)
    assert byte_size(encoded) > byte_size(payload)
    assert {:ok, decoded} = Heatshrink.decode(encoded)
    assert decoded == payload
  end

  test "rejects non-binary arguments" do
    for invalid <- [nil, :not_a_binary, 123, [1, 2, 3]] do
      assert_raise ArgumentError, fn -> Heatshrink.encode(invalid) end
      assert_raise ArgumentError, fn -> Heatshrink.decode(invalid) end
    end
  end
end
