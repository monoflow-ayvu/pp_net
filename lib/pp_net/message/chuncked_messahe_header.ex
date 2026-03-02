defmodule PPNet.Message.ChunckedMessageHeader do
  @moduledoc """
  Header for the ChunckedMessage message.
  """
  @behaviour PPNet.Message

  use TypedStruct

  @type_code 6

  typedstruct do
    field(:message_module, module(), enforce: true)
    field(:transaction_id, non_neg_integer(), enforce: true)
    field(:datetime, DateTime.t(), enforce: true)
    field(:total_chunks, non_neg_integer(), enforce: true)
  end

  @impl true
  def type_code, do: @type_code

  @impl true
  def pack(%__MODULE__{} = message) do
    <<
      message.message_module.type_code()::unsigned-integer-size(1)-unit(8),
      message.transaction_id::unsigned-integer-size(4)-unit(8),
      DateTime.to_unix(message.datetime)::unsigned-integer-size(4)-unit(8),
      message.total_chunks::unsigned-integer-size(1)-unit(8)
    >>
  end

  @impl true
  def parse(data) when is_binary(data) do
    raise "Not implemented"
  end
end
