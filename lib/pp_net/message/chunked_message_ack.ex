defmodule PPNet.Message.ChunkedMessageAck do
  @moduledoc """
  Transport-level ACK/NACK for a chunked message transfer, keyed by `transaction_id`.

  `status: :ok` confirms every chunk of a `ChunkedMessageHeader`/`ChunkedMessageBody`
  transfer was received and reassembled successfully — `missing_chunks` is empty.
  `status: :incomplete` signals the receiver is still missing chunks — `missing_chunks`
  lists the `chunk_index` values to retransmit, so the sender can resend only those
  chunks instead of the whole message.
  """
  @behaviour PPNet.Message

  use TypedStruct

  alias PPNet.PackError
  alias PPNet.ParseError

  @type_code 8
  @status_codes %{ok: 0, incomplete: 1, missing_header: 2}
  @status_codes_reverse Map.new(@status_codes, fn {k, v} -> {v, k} end)
  @statuses Map.keys(@status_codes)

  # | Field | Size |
  # | ---- | ---- |
  # | transaction_id | 4 bytes |
  # | status_code | 1 byte |
  # | missing_chunks_size | 1 byte |
  # | datetime | 4 bytes |
  @frame_overhead PPNet.frame_overhead()
  @fixed_fields_size 10

  @derive Jason.Encoder
  typedstruct do
    field(:transaction_id, non_neg_integer(), enforce: true)
    field(:status, atom(), enforce: true)
    field(:missing_chunks, [non_neg_integer()], default: [])
    field(:datetime, DateTime.t(), enforce: true)
  end

  @impl true
  def type_code, do: @type_code

  @impl true
  def datetime(%__MODULE__{datetime: datetime}), do: datetime

  @impl true
  def pack(%__MODULE__{} = message), do: pack(message, nil)

  @impl true
  def pack(
        %__MODULE__{
          transaction_id: transaction_id,
          status: status,
          missing_chunks: missing_chunks,
          datetime: %DateTime{} = datetime
        },
        limit
      )
      when is_integer(transaction_id) and transaction_id >= 0 and status in @statuses and is_list(missing_chunks) do
    missing_chunks_binary =
      missing_chunks
      |> Enum.sort()
      |> gen_delta()
      |> encode_varints()

    missing_chunks_size = byte_size(missing_chunks_binary)
    max_size = max_missing_chunks_size(limit)

    if missing_chunks_size <= max_size do
      <<
        transaction_id::unsigned-integer-size(4)-unit(8),
        @status_codes[status]::unsigned-integer-size(1)-unit(8),
        missing_chunks_size::unsigned-integer-size(1)-unit(8),
        missing_chunks_binary::binary-size(missing_chunks_size)-unit(8),
        DateTime.to_unix(datetime)::unsigned-integer-size(4)-unit(8)
      >>
    else
      {:error,
       %PackError{
         message:
           "missing_chunks takes #{missing_chunks_size} bytes encoded, exceeds the maximum of #{max_size} for limit #{inspect(limit)}",
         reason: :too_many_missing_chunks,
         data: %{count: length(missing_chunks), size: missing_chunks_size, max_size: max_size, limit: limit}
       }}
    end
  rescue
    error ->
      {:error, %PackError{message: "Invalid struct provided to pack/1", reason: {error, __STACKTRACE__}}}
  end

  def pack(_message, _limit) do
    {:error, %PackError{message: "Invalid struct provided to pack/1", reason: :invalid_struct}}
  end

  @impl true
  def parse(
        <<transaction_id::unsigned-integer-size(4)-unit(8), status_code::unsigned-integer-size(1)-unit(8),
          missing_chunks_size::unsigned-integer-size(1)-unit(8),
          missing_chunks_binary::binary-size(missing_chunks_size)-unit(8), datetime::unsigned-integer-size(4)-unit(8)>>
      ) do
    missing_chunks =
      missing_chunks_binary
      |> decode_varints()
      |> undelta()

    {:ok,
     %__MODULE__{
       transaction_id: transaction_id,
       status: @status_codes_reverse[status_code],
       missing_chunks: missing_chunks,
       datetime: DateTime.from_unix!(datetime)
     }}
  end

  def parse(data) do
    {:error,
     %ParseError{
       message: "The message body does not match the expected format",
       reason: :unknown_format,
       data: %{payload: data}
     }}
  end

  defp gen_delta([]), do: []

  defp gen_delta([first | rest]) do
    {deltas, _last} =
      Enum.map_reduce(rest, first, fn value, previous -> {value - previous, value} end)

    [first | deltas]
  end

  defp encode_varints(deltas) do
    for delta <- deltas, into: <<>>, do: encode_varint(delta)
  end

  defp encode_varint(n) when n < 128, do: <<0::1, n::7>>
  defp encode_varint(n), do: <<1::1, rem(n, 128)::7>> <> encode_varint(div(n, 128))

  defp undelta([]), do: []

  defp undelta([first | rest]) do
    {values, _last} =
      Enum.map_reduce(rest, first, fn delta, previous ->
        value = previous + delta
        {value, value}
      end)

    [first | values]
  end

  def decode_varints(<<>>), do: []

  def decode_varints(binary) do
    {value, rest} = decode_varint(binary)
    [value | decode_varints(rest)]
  end

  defp decode_varint(<<0::1, value::7, rest::binary>>), do: {value, rest}

  defp decode_varint(<<1::1, value::7, rest::binary>>) do
    {higher, remaining} = decode_varint(rest)
    {value + higher * 128, remaining}
  end

  defp max_missing_chunks_size(nil), do: max_missing_chunks_size(_ppnet_min_limit = 22)

  # Entries are delta+varint encoded, so how many fit depends on the gaps between them (1 to 3 bytes
  # each), not on their count. What is left of the frame after the fixed fields is the byte budget.
  defp max_missing_chunks_size(limit), do: limit - @frame_overhead - @fixed_fields_size
end
