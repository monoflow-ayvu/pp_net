defmodule PPNet do
  @moduledoc """
  Message protocol with error correction (Reed-Solomon) and framing (COBS).

  This module defines the `PPNet` module, which provides functions to parse
  a binary or list representation of a message into a struct.

  ## Encoding

  `encode_message/2` encodes a message struct into a binary frame ready to be sent.
  When the message exceeds the frame limit (default 254 bytes), it is automatically
  split into chunks and a list `[header_binary | chunk_binaries]` is returned.

      binary = PPNet.encode_message(%PPNet.Message.Hello{
        unique_id: "TestRunner",
        board_identifier: "Tester",
        version: 4660,
        board_version: 17_185,
        boot_id: 87_372_886,
        ppnet_version: 1
      })

      binary = PPNet.encode_message(%PPNet.Message.SingleCounter{
        kind: "bar",
        value: 42,
        pulses: 0,
        duration_ms: 1500
      })

      binary = PPNet.encode_message(%PPNet.Message.Ping{
        temperature: 25.0,
        uptime_ms: 3_600_000,
        location: %{lat: 40.7128, lon: -74.0060, accuracy: 10_000},
        cpu: 0.5,
        tpu_memory_percent: 50,
        tpu_ping_ms: 100,
        wifi: [%{mac: "00:1A:2B:3C:4D:5E", rssi: -42}],
        storage: %{total: 512_000, used: 128_000}
      })

      # Event — single frame
      binary = PPNet.encode_message(%PPNet.Message.Event{
        kind: :detection,
        data: %{"sensor_id" => 1, "value" => 100}
      })

      # Event — chunked when data is large
      [header_bin | chunk_bins] = PPNet.encode_message(%PPNet.Message.Event{
        kind: :detection,
        data: %{"image_id" => image_id, "d" => detections}
      })

      # Image — usually large enough to be chunked
      [header_bin | chunk_bins] = PPNet.encode_message(%PPNet.Message.Image{
        id: UUID.uuid4(),
        data: raw_binary,
        format: :webp
      })

  The optional `limit` parameter controls the maximum frame size in bytes (default 254).
  Use it to produce smaller chunks when the channel has tighter constraints:

      [header_bin | chunk_bins] = PPNet.encode_message(%PPNet.Message.Image{
        id: UUID.uuid4(),
        data: raw_binary,
        format: :webp
      }, limit: 100)

  ## Parsing

  `parse/1` accepts a binary or iodata and returns `%{messages: [...], errors: [...]}`.

  Each encoded message is wrapped with **COBS** (_Consistent Overhead Byte Stuffing_), which
  escapes the payload so it never contains the byte `0x00`. A `0x00` delimiter is then appended
  after each frame, allowing multiple messages to be concatenated in a stream and reliably
  separated on the receiver side. `parse/1` splits on `0x00` and decodes each frame automatically.

  Before parsing the message body, each frame is passed through **Reed-Solomon** error correction
  (8 parity bytes), which can transparently recover up to 4 corrupted bytes per frame. When
  corrections are made, a warning is logged. If corruption exceeds 4 bytes, the frame is
  discarded and an error is added to the result — but the remaining frames in the stream are
  still processed normally. Errors never interrupt the parsing of other messages.

      # Single message
      %{messages: [%PPNet.Message.Hello{unique_id: "TestRunner"}], errors: []} =
        PPNet.parse(binary)

      # Multiple messages concatenated in a stream
      %{messages: [%PPNet.Message.Ping{}, %PPNet.Message.SingleCounter{}], errors: []} =
        PPNet.parse(stream_binary)

      # Reed-Solomon corrects up to 4 corrupted bytes transparently
      %{messages: [%PPNet.Message.Hello{}], errors: []} = PPNet.parse(corrupted_binary)
      # A warning is logged: "Reed-Solomon corrected N errors in message of type ..."

      # More than 4 corrupted bytes — frame is discarded, other frames are unaffected
      %{
        messages: [%PPNet.Message.Ping{}],
        errors: [%PPNet.ParseError{reason: {:reed_solomon, "decode_failed"}}]
      } = PPNet.parse(stream_with_one_bad_frame)

      # Unknown or malformed frame
      %{
        messages: [],
        errors: [%PPNet.ParseError{reason: {:cobs, "Offset byte specifies more bytes than available"}}]
      } = PPNet.parse(garbage_binary)

  ### `PPNet.ParseError`

  Errors are returned as `%PPNet.ParseError{}` structs with the following fields:

  * `message` - Human-readable description of the error
  * `reason` - Machine-readable reason, e.g. `{:reed_solomon, "decode_failed"}`, `{:cobs, reason}`, `:unknown_format`, `:unknown_type`
  * `data` - Raw data associated with the failure, useful for debugging

  ## Limitations

  * Maximum frame size: **254 bytes** (COBS limit). Larger messages are automatically chunked.
  * Reed-Solomon can correct up to **4 corrupted bytes** per frame (8 parity bytes, GF(2⁸)).
  * Minimum chunk size: **17 bytes** (size of the `ChunkedMessageHeader` frame).

  ## Reassembling chunked messages

  After parsing a stream that contains chunked frames, use `chunked_to_message/1`
  to reassemble the original message:

      payload = Enum.join([header_bin | chunk_bins])

      %{messages: [header | chunks], errors: []} = PPNet.parse(payload)

      {:ok, %PPNet.Message.Image{data: ^raw_binary, format: :webp}} =
        PPNet.chunked_to_message([header | chunks])

  ## Message types

  | Type | Module                              |
  |------|-------------------------------------|
  | 1    | `PPNet.Message.Hello`               |
  | 2    | `PPNet.Message.SingleCounter`       |
  | 3    | `PPNet.Message.Ping`                |
  | 4    | `PPNet.Message.Event`               |
  | 5    | `PPNet.Message.Image`               |
  | 6    | `PPNet.Message.ChunkedMessageHeader`|
  | 7    | `PPNet.Message.ChunkedMessageBody`  |
  """
  alias PPNet.Message.ChunkedMessageBody
  alias PPNet.Message.ChunkedMessageHeader
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
  # Minimun chunk size is 17 bytes because this is the size of ChunkedMessageHeader
  @min_chunk_size 17

  @delimiter <<0>>

  @hello_type_code 1
  @single_counter_type_code 2
  @ping_type_code 3
  @event_type_code 4
  @image_type_code 5
  @chunked_message_header_type_code 6
  @chunked_message_body_type_code 7

  @type_codes [
    @hello_type_code,
    @single_counter_type_code,
    @ping_type_code,
    @event_type_code,
    @image_type_code,
    @chunked_message_header_type_code,
    @chunked_message_body_type_code
  ]

  @doc """
  Encodes a message struct into a COBS-framed, Reed-Solomon-protected binary.

  Returns a single binary when the message fits within `limit` bytes (default 254),
  or a list `[header_binary | chunk_binaries]` when the message is too large and must
  be split into chunks.

  ## Options

  * `:limit` - Maximum frame size in bytes. Defaults to 254. Values above 254 are clamped
    to 254; values below 17 (minimum chunk size) are clamped to 17.
  """
  def encode_message(%module{} = message, opts \\ []) do
    limit = get_limit(opts)

    packaged_data = module.pack(message)

    # type (1 byte) + packaged_data + Reed-Solomon overhead (8 bytes) + COBS overhead (1 byte) + separator (1 byte)
    total_size = 1 + byte_size(packaged_data) + 8 + 1 + 1

    if total_size <= limit do
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

  # credo:disable-for-next-line
  defp encode_chunked_message(binary, module, opts) do
    limit = get_limit(opts)
    # type (1 byte) + transaction_id (4 bytes) + chunk_index (1 byte) + chunk_size (1 byte)
    # + ReedSolomon overhead (8 bytes) + COBS overhead (1 byte) + separator (1 byte)
    chunk_header_size = 18
    chunk_size = limit - chunk_header_size
    transaction_id = transaction_id()
    datetime = DateTime.utc_now()

    chunks =
      binary
      |> :binary.bin_to_list()
      |> Enum.chunk_every(chunk_size)
      |> Enum.map(&IO.iodata_to_binary/1)

    total_chunks = length(chunks)

    header = %ChunkedMessageHeader{
      message_module: module,
      transaction_id: transaction_id,
      datetime: datetime,
      total_chunks: total_chunks
    }

    messages =
      for {chunk, index} <- Enum.with_index(chunks) do
        %ChunkedMessageBody{
          transaction_id: transaction_id,
          chunk_index: index,
          chunk_size: byte_size(chunk),
          chunk_data: chunk
        }
      end

    Enum.map([header | messages], &encode_message(&1, opts))
  end

  @doc """
  Parses a binary or iodata stream of COBS-framed messages.

  Splits the input on `0x00` delimiters, decodes each frame with COBS, applies
  Reed-Solomon error correction, and parses the message body. Returns a map with
  `:messages` and `:errors`. Failed frames are added to `:errors` without
  interrupting the processing of other frames.
  """
  def parse(data) when is_list(data), do: parse(IO.iodata_to_binary(data))

  # credo:disable-for-next-line
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

  @doc """
  Reassembles a chunked message from a `ChunkedMessageHeader` and its `ChunkedMessageBody` fragments.

  Expects a list starting with a `%ChunkedMessageHeader{}` followed by all corresponding
  `%ChunkedMessageBody{}` chunks. Fragments are sorted by `chunk_index` before reassembly.
  Returns `{:ok, message}` or `{:error, reason}`.
  """
  def chunked_to_message([
        %ChunkedMessageHeader{
          message_module: message_module,
          transaction_id: transaction_id,
          total_chunks: total_chunks
        } = header
        | chunks
      ])
      when total_chunks == length(chunks) do
    if Enum.all?(chunks, fn %ChunkedMessageBody{transaction_id: ^transaction_id} -> true end) do
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

  def chunked_to_message([%ChunkedMessageHeader{} | _chunks] = chunked_message) do
    {:error, build_error(chunked_message, :missing_chunks)}
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
  defp to_message_type(@chunked_message_header_type_code), do: ChunkedMessageHeader
  defp to_message_type(@chunked_message_body_type_code), do: ChunkedMessageBody

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
