defmodule PPNet do
  @moduledoc """
  This module defines the `PPNet` module, which provides functions to parse
  a binary or list representation of a message into a struct.
  """
  alias PPNet.Message.Hello
  alias PPNet.Message.ImageBody
  alias PPNet.Message.Ping
  alias PPNet.Message.SingleCounter
  alias PPNet.Message.ImageHeader
  alias PPNet.Message.Event
  alias PPNet.ParseError

  # Reed-Solomon is limited to 255 bytes inclusive
  # Cops is limited to 255 bytes exclusive
  @limit 254

  def run do
    image = File.read!("test/support/static/image.webp")

    limit = 200
    messages = encode_image(image, limit)

    IO.puts("Binary size: #{byte_size(image)}")
    IO.puts("Total messages: #{length(messages)} + 1 header message")
    IO.puts("ImageBody header size: 7")
    IO.puts("ImageBody chunk size: 200")
    IO.puts("Bynary bytes per message: #{limit - 13}")
    IO.puts("Total overhead: #{100 * 13 / limit}%")
  end

  def encode_message(%module{} = message, limit \\ @limit) when limit <= @limit do
    packaged_data = module.pack(message)

    # type (1 byte) + checksum (4 bytes) + packaged_data + separator (1 byte)
    total_size = 1 + 4 + 1 + 4 + byte_size(packaged_data)
    cops_overhead = ceil(total_size / 254)
    valid_total_size(limit, total_size + cops_overhead)

    checksum = :erlang.adler32(packaged_data)

    message = <<
      module.type_code()::unsigned-integer-size(1)-unit(8),
      checksum::32-big-unsigned-integer,
      packaged_data::binary-size(byte_size(packaged_data))-unit(8)
    >>

    {:ok, rs_encoded} = ReedSolomonEx.encode(message, 4)

    rs_encoded
    |> Cobs.encode!()
    |> Kernel.<>(<<0>>)
  end

  def encode_image(binary, chunk_size \\ @limit) do
    # type (1 byte) + checksum (4 bytes) + transaction_id (4 bytes) + chunk_index (1 byte) + chunk_size (2 bytes)
    # + ReedSolomon overhead (4 bytes) + separator (1 byte)
    chunk_header_size = 17
    transaction_id = transaction_id()

    cops_overhead = ceil(chunk_size / 254)

    chunks =
      binary
      |> :binary.bin_to_list()
      |> Enum.chunk_every(chunk_size - chunk_header_size - cops_overhead)
      |> Enum.map(&IO.iodata_to_binary/1)

    total_chunks = length(chunks)

    header =
      encode_message(
        %ImageHeader{
          transaction_id: transaction_id,
          total_chunks: total_chunks
        },
        chunk_size
      )

    messages =
      for {chunk, index} <- Enum.with_index(chunks) do
        encode_message(
          %ImageBody{
            transaction_id: transaction_id,
            chunk_index: index,
            chunk_data: chunk
          },
          chunk_size
        )
      end

    [header | messages]
  end

  @doc """
  Parses a binary or list representation of a message into a struct.
  """

  def parse(data) when is_list(data), do: parse(IO.iodata_to_binary(data))

  def parse(binary) when is_binary(binary) do
    binary
    |> :binary.split(<<0>>, [:global, :trim])
    |> Enum.reduce({[], []}, fn cobs_encoded, {messages, errors} ->
      with {:ok, cobs_decoded} <- cobs_decode(cobs_encoded),
           {:ok, rs_corrected} <- rs_correct(cobs_decoded),
           {:ok, message} <- decode_line(rs_corrected) do
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

  defp cobs_decode(data) do
    case Cobs.decode(data) do
      {:ok, cobs_decoded} ->
        {:ok, cobs_decoded}

      {:error, reason} ->
        {:error, build_error(data, {:cobs, reason})}
    end
  end

  defp rs_correct(data) do
    case ReedSolomonEx.correct(data, 4) do
      {:ok, rs_corrected} ->
        {:ok, rs_corrected}

      {:error, reason} ->
        {:error, build_error(data, {:reed_solomon, reason})}
    end
  rescue
    error ->
      {:error, build_error(data, {:reed_solomon, error})}
  end

  defp decode_line(
         <<type::unsigned-integer-size(1)-unit(8), checksum::unsigned-integer-size(4)-unit(8),
           packaged_body::binary>> = data
       )
       when type in [1, 2, 3, 4] do
    case to_message_type(type).parse(packaged_body) do
      {:ok, message} ->
        {:ok,
         struct(message,
           checksum: checksum,
           valid: :erlang.adler32(to_message_type(type).pack(message)) == checksum
         )}

      {:error, reason} ->
        error = build_error(type, packaged_body, reason, data)
        {:error, error}
    end
  end

  defp decode_line(
         <<5::unsigned-integer-size(1)-unit(8), checksum::unsigned-integer-size(4)-unit(8),
           transaction_id::unsigned-integer-size(4)-unit(8),
           total_chunks::unsigned-integer-size(1)-unit(8)>>
       ) do
    valid =
      :erlang.adler32(
        <<transaction_id::unsigned-integer-size(4)-unit(8),
          total_chunks::unsigned-integer-size(1)-unit(8)>>
      ) == checksum

    message = %ImageHeader{
      transaction_id: transaction_id,
      total_chunks: total_chunks,
      checksum: checksum,
      valid: valid
    }

    {:ok, message}
  end

  defp decode_line(
         <<6::unsigned-integer-size(1)-unit(8), checksum::unsigned-integer-size(4)-unit(8),
           transaction_id::unsigned-integer-size(4)-unit(8),
           chunk_index::unsigned-integer-size(1)-unit(8),
           chunk_size::unsigned-integer-size(2)-unit(8),
           chunk_data::binary-size(chunk_size)-unit(8)>>
       ) do
    valid =
      :erlang.adler32(
        <<transaction_id::unsigned-integer-size(4)-unit(8),
          chunk_index::unsigned-integer-size(1)-unit(8),
          chunk_size::unsigned-integer-size(2)-unit(8),
          chunk_data::binary-size(chunk_size)-unit(8)>>
      ) == checksum

    message = %ImageBody{
      transaction_id: transaction_id,
      chunk_index: chunk_index,
      chunk_data: chunk_data,
      chunk_size: chunk_size,
      checksum: checksum,
      valid: valid
    }

    {:ok, message}
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

  defp to_message_type(1), do: Hello
  defp to_message_type(2), do: SingleCounter
  defp to_message_type(3), do: Ping
  defp to_message_type(4), do: Event

  defp valid_total_size(limit, total_size) when is_integer(limit) and total_size > limit,
    do: raise("Total size must be less than or equal #{limit}")

  defp valid_total_size(_, _), do: :ok

  defp transaction_id do
    <<int::unsigned-integer-size(4)-unit(8)>> = :crypto.strong_rand_bytes(4)
    int
  end
end
