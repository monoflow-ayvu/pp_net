defmodule PPNet.Message.ChunkedMessageHeader do
  @moduledoc """
  Header for the ChunkedMessage message.
  """
  @behaviour PPNet.Message

  use TypedStruct

  alias PPNet.Message.ChunkedMessageHeader
  alias PPNet.Message.Event
  alias PPNet.Message.Hello
  alias PPNet.Message.Image
  alias PPNet.Message.Ping
  alias PPNet.Message.SingleCounter
  alias PPNet.ParseError

  @type_code 6
  @derive Jason.Encoder

  @hello_type_code 1
  @single_counter_type_code 2
  @ping_type_code 3
  @event_type_code 4
  @image_type_code 5
  @valid_message_modules [Hello, SingleCounter, Ping, Event, Image]

  typedstruct do
    @typedoc """
    The `PPNet.Message.ChunkedMessageHeader` struct

    ## Fields

    * `message_module` - The module of the original message being chunked
    * `transaction_id` - Unique ID grouping all chunks of the same message
    * `datetime` - Timestamp of when the message was sent
    * `total_chunks` - Total number of chunks the message was split into
    """

    field(:message_module, module(), enforce: true)
    field(:transaction_id, non_neg_integer(), enforce: true)
    field(:datetime, DateTime.t(), enforce: true)
    field(:total_chunks, non_neg_integer(), enforce: true)
  end

  @impl true
  def type_code, do: @type_code

  @impl true
  def pack(%__MODULE__{
        message_module: message_module,
        transaction_id: transaction_id,
        datetime: %DateTime{} = datetime,
        total_chunks: total_chunks
      })
      when message_module in @valid_message_modules and is_integer(transaction_id) and is_integer(total_chunks) do
    <<
      message_module.type_code()::unsigned-integer-size(1)-unit(8),
      transaction_id::unsigned-integer-size(4)-unit(8),
      DateTime.to_unix(datetime)::unsigned-integer-size(4)-unit(8),
      total_chunks::unsigned-integer-size(2)-unit(8)
    >>
  end

  def pack(_message) do
    {:error, %ParseError{message: "Invalid struct provided to pack/1", reason: :invalid_struct}}
  end

  @impl true
  def parse(
        <<message_module_code::unsigned-integer-size(1)-unit(8), transaction_id::unsigned-integer-size(4)-unit(8),
          datetime_unix::unsigned-integer-size(4)-unit(8), total_chunks::unsigned-integer-size(2)-unit(8)>>
      ) do
    {:ok, datetime} = DateTime.from_unix(datetime_unix)

    message = %ChunkedMessageHeader{
      message_module: to_message_type(message_module_code),
      transaction_id: transaction_id,
      datetime: datetime,
      total_chunks: total_chunks
    }

    {:ok, message}
  end

  def parse(data) when is_list(data) do
    {:error,
     %ParseError{
       message: "The message body does not match the expected format",
       reason: :unknown_format,
       data: {:body, data}
     }}
  end

  defp to_message_type(@hello_type_code), do: Hello
  defp to_message_type(@single_counter_type_code), do: SingleCounter
  defp to_message_type(@ping_type_code), do: Ping
  defp to_message_type(@event_type_code), do: Event
  defp to_message_type(@image_type_code), do: Image
end
