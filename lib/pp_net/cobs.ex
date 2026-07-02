defmodule PPNet.Cobs do
  @moduledoc false
  # COBS encoder for the encode path. `Cobs.encode!/1` appends byte-at-a-time,
  # which is slow on no-JIT embedded targets. Output (and the ArgumentError on
  # oversized input) is byte-identical to `Cobs.encode!/1`: frames are at most
  # 254 bytes, so no zero-delimited block can exceed 253 data bytes and the
  # 255-code block continuation of full COBS never arises.

  def encode_iodata!(binary) when byte_size(binary) > 254 do
    raise ArgumentError, "Binary too long"
  end

  def encode_iodata!(binary) do
    binary
    |> :binary.split(<<0>>, [:global])
    |> Enum.map(fn block -> [byte_size(block) + 1, block] end)
  end
end
