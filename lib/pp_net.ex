defmodule PPNet do
  @moduledoc """
  Message protocol with error correction (Reed-Solomon) and framing (COBS).

  For the full protocol specification, see the [README](readme.html).

  ## Encoding

  `encode_message/2` encodes a message struct into a binary frame ready to be sent.
  When the message exceeds the frame limit (default 254 bytes), it is automatically
  split into chunks and a list `[header_binary | chunk_binaries]` is returned.

      iex> %PPNet.Message.Hello{
      ...>   unique_id: "TestRunner",
      ...>   board_identifier: "Tester",
      ...>   version: 4660,
      ...>   board_version: 17_185,
      ...>   boot_id: 87_372_886,
      ...>   ppnet_version: 1,
      ...>   datetime: ~U[2026-03-26 21:00:55.352750Z]
      ...> } |> PPNet.encode_message()
      <<46, 1, 151, 170, 84, 101, 115, 116, 82, 117, 110, 110, 101, 114, 166, 84, 101,
        115, 116, 101, 114, 205, 18, 52, 205, 67, 33, 206, 5, 53, 52, 86, 1, 206, 105,
        197, 158, 135, 37, 216, 194, 76, 126, 139, 15, 150, 0>>

      iex> %PPNet.Message.SingleCounter{
      ...>   kind: "bar",
      ...>   value: 42,
      ...>   pulses: 0,
      ...>   duration_ms: 1500,
      ...>   datetime: ~U[2026-03-27 12:58:06Z]
      ...> } |> PPNet.encode_message()
      <<8, 2, 149, 163, 98, 97, 114, 42, 17, 205, 5, 220, 206, 105, 198, 126, 222, 52,
        64, 141, 44, 85, 238, 249, 45, 0>>

      iex> %PPNet.Message.Ping{
      ...>   session_id: "5388724c-457e-4332-a98c-e67b2053662c",
      ...>   temperature: 25.0,
      ...>   uptime_ms: 3_600_000,
      ...>   location: %{lat: 40.7128, lon: -74.0060, accuracy: 10_000},
      ...>   cpu: 0.5,
      ...>   tpu_memory_percent: 50,
      ...>   tpu_ping_ms: 100,
      ...>   wifi: [%{mac: "00:1A:2B:3C:4D:5E", rssi: -42}],
      ...>   storage: %{total: 512_000, used: 128_000}
      ...> } |> PPNet.encode_message()
      <<4, 3, 154, 220, 25, 16, 83, 204, 136, 114, 76, 69, 126, 67, 50, 204, 169, 204,
        140, 204, 230, 123, 32, 83, 102, 44, 203, 64, 57, 1, 1, 1, 1, 1, 2, 206, 29,
        54, 238, 128, 147, 203, 64, 68, 91, 61, 7, 200, 75, 94, 203, 192, 82, 128, 98,
        77, 210, 241, 170, 205, 39, 16, 203, 63, 224, 1, 1, 1, 1, 1, 5, 50, 100, 145,
        167, 9, 26, 43, 60, 77, 94, 214, 146, 206, 3, 7, 208, 2, 206, 3, 1, 244, 10,
        128, 234, 62, 197, 142, 226, 20, 6, 217, 0>>

      iex> %PPNet.Message.Event{
      ...>   kind: :detection,
      ...>   data: %{"sensor_id" => 1, "value" => 100}
      ...> } |> PPNet.encode_message()
      <<31, 4, 146, 1, 130, 165, 118, 97, 108, 117, 101, 100, 169, 115, 101, 110, 115,
        111, 114, 95, 105, 100, 1, 132, 127, 245, 70, 100, 161, 64, 158, 0>>

  Event can also be chunked when the data payload is large:

      # [header_bin | chunk_bins] = PPNet.encode_message(%PPNet.Message.Event{
      #   kind: :detection,
      #   data: %{"image_id" => image_id, "d" => detections}
      # })

  Image is usually large enough to be chunked:

      iex> image_data = File.read!("test/support/static/image.webp")
      iex> image = %PPNet.Message.Image{
      ...>   id: "00000000-0000-0000-0000-000000000000",
      ...>   data: image_data,
      ...>   format: :webp
      ...> }
      iex> [header_bin | chunks_bin] = PPNet.encode_message(image)
      iex> %{messages: [header | chunks], errors: []} = PPNet.parse([header_bin | chunks_bin])
      iex> PPNet.chunked_to_message([header | chunks])
      {:ok, %PPNet.Message.Image{id: "00000000-0000-0000-0000-000000000000", format: :webp, data: image_data}}


  The optional `limit` parameter controls the maximum frame size in bytes (default 254).
  Use it to produce smaller chunks when the channel has tighter constraints:

      iex> image_data = File.read!("test/support/static/image.webp")
      iex> [_header | chunks] = PPNet.encode_message(
      ...>   %PPNet.Message.Image{
      ...>     id: "00000000-0000-0000-0000-000000000000",
      ...>     data: image_data,
      ...>     format: :webp
      ...>   },
      ...>   limit: 100
      ...> )
      iex> Enum.all?(chunks, &(byte_size(&1) <= 100))
      true

  ## Parsing

  `parse/1` accepts a binary or iodata and returns `%{messages: [...], errors: [...]}`.

  Each encoded message is wrapped with **COBS** (_Consistent Overhead Byte Stuffing_), which
  escapes the payload so it never contains the byte `0x00`. A `0x00` delimiter is then appended
  after each frame, allowing multiple messages to be concatenated in a stream and reliably
  separated on the receiver side. `parse/1` splits on `0x00` and decodes each frame automatically.

  Every binary returned by `encode_message/2` — including each chunk in a chunked message —
  already includes the `0x00` delimiter at the end. Concatenating them with `Enum.join/1` is
  therefore sufficient; no extra separator is needed.

  Before parsing the message body, each frame is passed through **Reed-Solomon** error correction
  (8 parity bytes), which can transparently recover up to 4 corrupted bytes per frame. When
  corrections are made, a warning is logged. If corruption exceeds 4 bytes, the frame is
  discarded and an error is added to the result — but the remaining frames in the stream are
  still processed normally. Errors never interrupt the parsing of other messages.

      iex> hello = %PPNet.Message.Hello{
      ...>   unique_id: "TestRunner",
      ...>   board_identifier: "Tester",
      ...>   version: 4660,
      ...>   board_version: 17_185,
      ...>   boot_id: 87_372_886,
      ...>   ppnet_version: 1,
      ...>   datetime: ~U[2026-03-26 21:00:55Z]
      ...> }
      iex> hello |> PPNet.encode_message() |> PPNet.parse() |> Map.get(:messages) |> hd() == hello
      true

  Reed-Solomon corrects up to 4 corrupted bytes transparently — a warning is logged when
  corrections are made. If corruption exceeds 4 bytes, the frame is discarded and an error
  is returned, but remaining frames in the stream are still processed normally:

      # %{
      #   messages: [%PPNet.Message.Ping{}],
      #   errors: [%PPNet.ParseError{reason: {:reed_solomon, "decode_failed"}}]
      # } = PPNet.parse(stream_with_one_bad_frame)

      # %{
      #   messages: [],
      #   errors: [%PPNet.ParseError{reason: {:cobs, "Offset byte specifies more bytes than available"}}]
      # } = PPNet.parse(garbage_binary)

  ### `PPNet.ParseError`

  Errors are returned as `%PPNet.ParseError{}` structs with the following fields:

  * `message` - Human-readable description of the error
  * `reason` - Machine-readable reason, e.g. `{:reed_solomon, "decode_failed"}`, `{:cobs, reason}`, `:unknown_format`, `:unknown_type`
  * `data` - Raw data associated with the failure, useful for debugging

  ## Limitations

  * Maximum frame size: **254 bytes** (COBS limit). Larger messages are automatically chunked.
  * Minimum chunk size: **17 bytes** — the encoded size of a `ChunkedMessageHeader` frame. Going
    below this would cause the header itself to be chunked, which is not supported.
  * Reed-Solomon can correct up to **4 corrupted bytes** per frame (8 parity bytes, GF(2⁸)).

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
  # Minimun chunk size is 22 bytes because this is the size of ChunkedMessageHeader
  @min_chunk_size 22

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

  * `:limit` - Maximum frame size in bytes. Defaults to 254. Clamped to the range `17..254`.
    The minimum of 17 matches the encoded size of a `ChunkedMessageHeader` frame — going below
    that would cause the header itself to be chunked. 254 is the COBS limit.
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
    # type (1 byte) + transaction_id (4 bytes) + chunk_index (2 bytes) + chunk_size (1 byte)
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
