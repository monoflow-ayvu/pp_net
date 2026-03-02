defmodule PPNet.Message.ChunckedMessageHeader do
  @moduledoc """
  Header for the ChunckedMessage message.
  """
  @behaviour PPNet.Message

  use TypedStruct

  alias PPNet.Message.Event
  alias PPNet.Message.Hello
  alias PPNet.Message.Image
  alias PPNet.Message.Ping
  alias PPNet.Message.SingleCounter
  alias PPNet.ParseError

  @type_code 6

  typedstruct do
    field(:message_module, module(), enforce: true)
    field(:transaction_id, non_neg_integer(), enforce: true)
    field(:datetime, DateTime.t(), enforce: true)
    field(:total_chunks, non_neg_integer(), enforce: true)
    field(:checksum, non_neg_integer())
    field(:valid, boolean())
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
  def parse(
        <<message_module_code::unsigned-integer-size(1)-unit(8), transaction_id::unsigned-integer-size(4)-unit(8),
          datetime_unix::unsigned-integer-size(4)-unit(8), total_chunks::unsigned-integer-size(1)-unit(8),
          checksum::unsigned-integer-size(4)-unit(8)>>
      ) do
    {:ok,
     %__MODULE__{
       message_module: message_module_code_to_module(message_module_code),
       transaction_id: transaction_id,
       datetime: DateTime.from_unix!(datetime_unix),
       total_chunks: total_chunks,
       checksum: checksum
     }}
  end

  @impl true
  def parse(data) do
    {:error,
     %ParseError{
       message: "The message body does not match the expected format",
       reason: :unknown_format,
       data: %{payload: data}
     }}
  end

  def message_module_code_to_module(1), do: Hello
  def message_module_code_to_module(2), do: SingleCounter
  def message_module_code_to_module(3), do: Ping
  def message_module_code_to_module(4), do: Event
  def message_module_code_to_module(5), do: Image
end
