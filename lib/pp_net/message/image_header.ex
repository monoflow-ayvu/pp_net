defmodule PPNet.Message.ImageHeader do
  use TypedStruct

  @type_code 3

  typedstruct do
    field(:transaction_id, non_neg_integer(), enforce: true)
    field(:total_chunks, non_neg_integer(), enforce: true)
  end

  def type_code, do: @type_code

  def pack(%__MODULE__{} = header) do
    <<header.transaction_id::unsigned-integer-size(4)-unit(8),
      header.total_chunks::unsigned-integer-size(1)-unit(8)>>
  end
end
