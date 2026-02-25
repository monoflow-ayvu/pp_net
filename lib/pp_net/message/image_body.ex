defmodule PPNet.Message.ImageBody do
  use TypedStruct

  @type_code 4

  typedstruct do
    field(:transaction_id, non_neg_integer(), enforce: true)
    field(:chunk_index, non_neg_integer(), enforce: true)
    field(:chunk_data, binary(), enforce: true)
  end

  def type_code, do: @type_code

  def pack(%__MODULE__{} = body) do
    <<
      body.transaction_id::unsigned-integer-size(4)-unit(8),
      body.chunk_index::unsigned-integer-size(1)-unit(8),
      body.chunk_data::binary
    >>
  end
end
