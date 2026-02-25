defmodule PPNet.Message.ImageHeader do
  @moduledoc """
  This module defines the `PPNet.Message.ImageHeader` struct and provides functions to parse
  a binary or list representation of an ImageHeader message into this struct.
  """
  use TypedStruct

  @type_code 3

  typedstruct do
    field(:transaction_id, non_neg_integer(), enforce: true)
    field(:total_chunks, non_neg_integer(), enforce: true)
  end

  def type_code, do: @type_code

  def pack(%__MODULE__{total_chunks: total_chunks} = header) when total_chunks <= 255 do
    <<header.transaction_id::unsigned-integer-size(4)-unit(8),
      header.total_chunks::unsigned-integer-size(1)-unit(8)>>
  end
end
