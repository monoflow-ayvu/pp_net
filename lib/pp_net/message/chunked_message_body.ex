defmodule PPNet.Message.ChunkedMessageBody do
  @moduledoc """
  Body for the ChunkedMessage message.
  """
  @behaviour PPNet.Message

  use TypedStruct

  alias PPNet.Message.ChunkedMessageBody
  alias PPNet.PackError
  alias PPNet.ParseError

  @type_code 7
  @derive Jason.Encoder

  @max_transaction_id 2 ** 32 - 1
  @max_chunk_index 2 ** 16 - 1

  defguard is_transaction_id_valid(transaction_id)
           when is_integer(transaction_id) and transaction_id >= 0 and transaction_id <= @max_transaction_id

  defguard is_chunk_index_valid(chunk_index)
           when is_integer(chunk_index) and chunk_index >= 0 and
                  chunk_index <= @max_chunk_index

  typedstruct do
    @typedoc """
    The `PPNet.Message.ChunkedMessageBody` struct

    ## Fields

    * `transaction_id` - Matches the `transaction_id` from the corresponding `ChunkedMessageHeader`
    * `chunk_index` - Zero-based index of this chunk within the full message
    * `chunk_size` - Size in bytes of `chunk_data`
    * `chunk_data` - Raw binary fragment of the original message
    """

    field(:transaction_id, non_neg_integer(), enforce: true)
    field(:datetime, DateTime.t(), enforce: true)
    field(:chunk_index, non_neg_integer(), enforce: true)
    field(:chunk_size, non_neg_integer(), enforce: true)
    field(:chunk_data, binary(), enforce: true)
  end

  @impl true
  def type_code, do: @type_code

  @impl true
  def datetime(%__MODULE__{datetime: datetime}), do: datetime

  @impl true
  def pack(%__MODULE__{
        transaction_id: transaction_id,
        datetime: %DateTime{} = datetime,
        chunk_index: chunk_index,
        chunk_size: chunk_size,
        chunk_data: chunk_data
      })
      when is_transaction_id_valid(transaction_id) and is_chunk_index_valid(chunk_index) and is_integer(chunk_size) and
             chunk_size <= 254 and is_binary(chunk_data) do
    <<
      transaction_id::unsigned-integer-size(4)-unit(8),
      DateTime.to_unix(datetime)::unsigned-integer-size(4)-unit(8),
      chunk_index::unsigned-integer-size(2)-unit(8),
      chunk_size::unsigned-integer-size(1)-unit(8),
      chunk_data::binary-size(chunk_size)-unit(8)
    >>
  rescue
    error ->
      {:error, %PackError{message: "Invalid struct provided to pack/1", reason: {error, __STACKTRACE__}}}
  end

  def pack(_message) do
    {:error, %PackError{message: "Invalid struct provided to pack/1", reason: :invalid_struct}}
  end

  @impl true
  def parse(
        <<transaction_id::unsigned-integer-size(4)-unit(8), datetime::unsigned-integer-size(4)-unit(8),
          chunk_index::unsigned-integer-size(2)-unit(8), chunk_size::unsigned-integer-size(1)-unit(8),
          chunk_data::binary-size(chunk_size)-unit(8)>>
      ) do
    message = %ChunkedMessageBody{
      transaction_id: transaction_id,
      datetime: DateTime.from_unix!(datetime),
      chunk_index: chunk_index,
      chunk_size: chunk_size,
      chunk_data: chunk_data
    }

    {:ok, message}
  end

  def parse(
        <<transaction_id::unsigned-integer-size(4)-unit(8), chunk_index::unsigned-integer-size(2)-unit(8),
          chunk_size::unsigned-integer-size(1)-unit(8), chunk_data::binary-size(chunk_size)-unit(8)>>
      ) do
    message = %ChunkedMessageBody{
      transaction_id: transaction_id,
      datetime: nil,
      chunk_index: chunk_index,
      chunk_size: chunk_size,
      chunk_data: chunk_data
    }

    {:ok, message}
  end

  def parse(data) do
    {:error,
     %ParseError{
       message: "The message body does not match the expected format",
       reason: :unknown_format,
       data: {:body, data}
     }}
  end
end
