defmodule PPNet.Test.Helper do
  def corrupt_bytes(payload, positions) do
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
end
