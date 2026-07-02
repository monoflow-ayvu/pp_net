defmodule PPNetCobsTest do
  use ExUnit.Case, async: true

  defp encode(binary), do: IO.iodata_to_binary(PPNet.Cobs.encode_iodata!(binary))

  describe "encode_iodata!/1" do
    test "is byte-identical to Cobs.encode!/1 on boundary inputs" do
      cases = [
        <<>>,
        <<0>>,
        <<0, 0, 0>>,
        <<1, 2, 3>>,
        <<0, 1, 2>>,
        <<1, 2, 0>>,
        <<1, 0, 2, 0, 3>>,
        :binary.copy(<<0xFF>>, 254),
        :binary.copy(<<0>>, 254),
        <<0>> <> :binary.copy(<<7>>, 252) <> <<0>>
      ]

      for input <- cases do
        assert encode(input) == Cobs.encode!(input)
      end
    end

    test "is byte-identical to Cobs.encode!/1 for random inputs of every valid size" do
      for size <- 0..254 do
        input = :crypto.strong_rand_bytes(size)
        zero_heavy = for <<byte <- input>>, into: <<>>, do: <<if(byte < 64, do: 0, else: byte)>>

        for bin <- [input, zero_heavy] do
          encoded = encode(bin)
          assert encoded == Cobs.encode!(bin)
          assert Cobs.decode!(encoded) == bin
        end
      end
    end

    test "raises on input longer than 254 bytes, like Cobs.encode!/1" do
      assert_raise ArgumentError, fn -> PPNet.Cobs.encode_iodata!(:binary.copy(<<1>>, 255)) end
    end
  end
end
