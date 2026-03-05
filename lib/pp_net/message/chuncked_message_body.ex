defmodule PPNet.Message.ChunckedMessageBody do
  @moduledoc """
  Body for the ChunckedMessage message.
  """
  @behaviour PPNet.Message

  use TypedStruct

  alias PPNet.Message.ChunckedMessageBody
  alias PPNet.ParseError

  @type_code 7
  @derive Jason.Encoder

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
      body.chunk_index::unsigned-integer-size(2)-unit(8),
      body.chunk_size::unsigned-integer-size(1)-unit(8),
      body.chunk_data::binary-size(body.chunk_size)-unit(8)
    >>
  end

  @impl true
  def parse(
        <<transaction_id::unsigned-integer-size(4)-unit(8), chunk_index::unsigned-integer-size(2)-unit(8),
          chunk_size::unsigned-integer-size(1)-unit(8), chunk_data::binary-size(chunk_size)-unit(8)>>
      ) do
    message = %ChunckedMessageBody{
      transaction_id: transaction_id,
      chunk_index: chunk_index,
      chunk_size: chunk_size,
      chunk_data: chunk_data
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
end
