defmodule PPNet.Message.ChunckedMessageBody do
  @moduledoc """
  Body for the ChunckedMessage message.
  """
  @behaviour PPNet.Message

  use TypedStruct

  @type_code 7

  typedstruct do
    field(:transaction_id, non_neg_integer(), enforce: true)
    field(:chunk_index, non_neg_integer(), enforce: true)
    field(:chunk_size, non_neg_integer(), enforce: true)
    field(:chunk_data, binary(), enforce: true)
  end

  @impl true
  def type_code, do: @type_code

  @impl true
  def pack(%__MODULE__{} = body) do
    <<
      body.transaction_id::unsigned-integer-size(4)-unit(8),
      body.chunk_index::unsigned-integer-size(1)-unit(8),
      body.chunk_size::unsigned-integer-size(1)-unit(8),
      body.chunk_data::binary-size(body.chunk_size)-unit(8)
    >>
  end

  @impl true
  def parse(data) when is_binary(data) do
    raise "Not implemented"
  end
end
