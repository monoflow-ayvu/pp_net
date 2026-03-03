defmodule PPNet do
  @moduledoc """
  This module defines the `PPNet` module, which provides functions to parse
  a binary or list representation of a message into a struct.
  """
  alias PPNet.Message.ChunckedMessageBody
  alias PPNet.Message.ChunckedMessageHeader
  alias PPNet.Message.Event
  alias PPNet.Message.Hello
  alias PPNet.Message.Image
  alias PPNet.Message.Ping
  alias PPNet.Message.SingleCounter
  alias PPNet.ParseError

  require Logger

  # Reed-Solomon is limited to 255 bytes inclusive
  # Cops is limited to 255 bytes exclusive
  @limit 254
  # Minimun chunk size is 17 bytes because this is the size of ChunckedMessageHeader
  @min_chunk_size 17

  @delimiter <<0>>

  @hello_type_code 1
  @single_counter_type_code 2
  @ping_type_code 3
  @event_type_code 4
  @image_type_code 5
  @chuncked_message_header_type_code 6
  @chuncked_message_body_type_code 7

  @type_codes [
    @hello_type_code,
    @single_counter_type_code,
    @ping_type_code,
    @event_type_code,
    @image_type_code,
    @chuncked_message_header_type_code,
    @chuncked_message_body_type_code
  ]

  def encode_message(%module{} = message, opts \\ []) do
    limit = get_limit(opts)

    packaged_data = module.pack(message)

    # type (1 byte) + packaged_data + Reed-Solomon overhead (8 bytes) + separator (1 byte)
    total_size = 1 + byte_size(packaged_data) + 8 + 1
    cops_overhead = ceil(total_size / 254)

    if total_size + cops_overhead <= limit do
      message = <<
        module.type_code()::unsigned-integer-size(1)-unit(8),
        packaged_data::binary-size(byte_size(packaged_data))-unit(8)
      >>

      {:ok, rs_encoded} = ReedSolomonEx.encode(message, 8)

      rs_encoded
      |> Cobs.encode!()
      |> Kernel.<>(@delimiter)
    else
      encode_chunked_message(packaged_data, module, opts)
    end
  end

  defp encode_chunked_message(binary, module, opts) do
    limit = get_limit(opts)
    # type (1 byte) + transaction_id (4 bytes) + chunk_index (1 byte) + chunk_size (1 byte)
    # + ReedSolomon overhead (8 bytes) + separator (1 byte)
    chunk_header_size = 17
    cops_overhead = ceil(limit / 254)
    chunk_size = limit - chunk_header_size - cops_overhead
    transaction_id = transaction_id()
    datetime = DateTime.utc_now()

    chunks =
      binary
      |> :binary.bin_to_list()
      |> Enum.chunk_every(chunk_size)
      |> Enum.map(&IO.iodata_to_binary/1)

    total_chunks = length(chunks)

    header = %ChunckedMessageHeader{
      message_module: module,
      transaction_id: transaction_id,
      datetime: datetime,
      total_chunks: total_chunks
    }

    messages =
      for {chunk, index} <- Enum.with_index(chunks) do
        %ChunckedMessageBody{
          transaction_id: transaction_id,
          chunk_index: index,
          chunk_size: byte_size(chunk),
          chunk_data: chunk
        }
      end

    Enum.map([header | messages], &encode_message(&1, opts))
  end

  @doc """
  Parses a binary or list representation of a message into a struct.
  """

  def parse(data) when is_list(data), do: parse(IO.iodata_to_binary(data))

  def parse(binary) when is_binary(binary) do
    binary
    |> :binary.split(@delimiter, [:global, :trim])
    |> Enum.reduce({[], []}, fn cobs_encoded, {messages, errors} ->
      with {:ok, cobs_decoded} <- cobs_decode(cobs_encoded),
           {:ok, {rs_corrected, err_count}} <- rs_correct(cobs_decoded),
           {:ok, message} <- decode_line(rs_corrected) do
        maybe_log_error(message, err_count)

        {[message | messages], errors}
      else
        {:error, %ParseError{} = error} ->
          {messages, [error | errors]}

        {:error, reason} ->
          {messages, [build_error(cobs_encoded, reason) | errors]}

        error ->
          {messages, [build_error(cobs_encoded, error) | errors]}
      end
    end)
    |> then(fn {messages, errors} ->
      %{messages: Enum.reverse(messages), errors: Enum.reverse(errors)}
    end)
  end

  defp maybe_log_error(_message, 0), do: :ok

  defp maybe_log_error(%{__struct__: struct}, err_count) do
    Logger.info("Reed-Solomon corrected #{err_count} errors in message of type #{struct}")
  end

  defp cobs_decode(data) do
    case Cobs.decode(data) do
      {:ok, cobs_decoded} ->
        {:ok, cobs_decoded}

      {:error, reason} ->
        {:error, build_error(data, {:cobs, reason})}
    end
  end

  def chuncked_to_message([
        %ChunckedMessageHeader{
          message_module: message_module,
          transaction_id: transaction_id,
          total_chunks: total_chunks
        } = header
        | chunks
      ])
      when total_chunks == length(chunks) do
    if Enum.all?(chunks, fn %ChunckedMessageBody{transaction_id: ^transaction_id} -> true end) do
      binary =
        chunks
        |> Enum.sort_by(& &1.chunk_index)
        |> Enum.map_join("", & &1.chunk_data)

      case message_module.parse(binary) do
        {:ok, message} ->
          {:ok, message}

        {:error, reason} ->
          {:error, build_error(header, reason)}
      end
    else
      {:error, build_error(header, :invalid_transaction_id)}
    end
  end

  def chuncked_to_message([%ChunckedMessageHeader{} | _chunks] = chuncked_message) do
    {:error, build_error(chuncked_message, :missing_chunks)}
  end

  defp rs_correct(data) do
    case ReedSolomonEx.correct_err_count(data, 8) do
      {:ok, {rs_corrected, err_count}} ->
        {:ok, {rs_corrected, err_count}}

      {:error, reason} ->
        {:error, build_error(data, {:reed_solomon, reason})}
    end
  rescue
    error ->
      {:error, build_error(data, {:reed_solomon, error})}
  end

  defp decode_line(<<type_code::unsigned-integer-size(1)-unit(8), packaged_body::binary>> = data)
       when type_code in @type_codes do
    case to_message_type(type_code).parse(packaged_body) do
      {:ok, message} ->
        {:ok, message}

      {:error, reason} ->
        error = build_error(type_code, packaged_body, reason, data)
        {:error, error}
    end
  end

  defp decode_line(data), do: {:error, build_error(data)}

  defp build_error(type, body, reason, payload) do
    %ParseError{
      message: "Failed to parse message of type #{type}",
      reason: reason,
      data: %{type: type, body: body, payload: payload}
    }
  end

  defp build_error(payload, reason) do
    %ParseError{
      message: "Failed to parse message",
      reason: reason,
      data: %{payload: payload}
    }
  end

  defp build_error(payload) do
    build_error(payload, :unknown_type)
  end

  defp to_message_type(@hello_type_code), do: Hello
  defp to_message_type(@single_counter_type_code), do: SingleCounter
  defp to_message_type(@ping_type_code), do: Ping
  defp to_message_type(@event_type_code), do: Event
  defp to_message_type(@image_type_code), do: Image
  defp to_message_type(@chuncked_message_header_type_code), do: ChunckedMessageHeader
  defp to_message_type(@chuncked_message_body_type_code), do: ChunckedMessageBody

  defp transaction_id do
    <<int::unsigned-integer-size(4)-unit(8)>> = :crypto.strong_rand_bytes(4)
    int
  end

  defp get_limit(opts) do
    limit = opts[:limit]

    cond do
      is_integer(limit) and limit > @limit -> @limit
      is_integer(limit) and limit < @min_chunk_size -> @min_chunk_size
      is_integer(limit) and limit <= @limit -> limit
      true -> @limit
    end
  end
end
