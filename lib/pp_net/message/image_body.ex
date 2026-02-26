defmodule PPNet.Message.ImageBody do
  @moduledoc """
  This module defines the `PPNet.Message.ImageBody` struct and provides functions to parse
  a binary or list representation of an ImageBody message into this struct.
  """
  use TypedStruct

  @type_code 6

  typedstruct do
    field(:transaction_id, non_neg_integer(), enforce: true)
    field(:chunk_index, non_neg_integer(), enforce: true)
    field(:chunk_size, non_neg_integer())
    field(:chunk_data, binary(), enforce: true)
    field(:checksum, non_neg_integer())
    field(:valid, boolean())
  end

  def type_code, do: @type_code

  def pack(%__MODULE__{} = body) do
    chunk_size = byte_size(body.chunk_data)

    <<
      body.transaction_id::unsigned-integer-size(4)-unit(8),
      body.chunk_index::unsigned-integer-size(1)-unit(8),
      chunk_size::unsigned-integer-size(2)-unit(8),
      body.chunk_data::binary-size(chunk_size)-unit(8)
    >>
  end
end
