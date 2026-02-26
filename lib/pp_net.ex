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

  def encode_message(%module{} = message, limit \\ :unlimited) do
    packaged_data = module.pack(message)

    total_size = 1 + 4 + byte_size(packaged_data)
    valid_total_size(limit, total_size)

    checksum = :erlang.adler32(packaged_data)

    <<
      module.type_code()::unsigned-integer-size(1)-unit(8),
      checksum::32-big-unsigned-integer,
      packaged_data::binary-size(byte_size(packaged_data))-unit(8)
    >>
  end

  def encode_image(binary, chunk_size \\ :unlimited) do
    # type (1 byte) + checksum (4 bytes) + transaction_id (4 bytes) + chunk_index (1 byte) + chunk_size (2 bytes)
    chunk_header_size = 13
    transaction_id = transaction_id()

    chunks =
      case chunk_size do
        :unlimited ->
          [binary]

        size when is_integer(size) and size > chunk_header_size ->
          binary
          |> :binary.bin_to_list()
          |> Enum.chunk_every(chunk_size - chunk_header_size)
          |> Enum.map(&IO.iodata_to_binary/1)
      end

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
    {messages, errors} = decode_line(binary)

    %{messages: messages, errors: errors}
  end

  defp decode_line(data, messages \\ [], errors \\ [], buffer \\ <<>>)

  defp decode_line(<<>>, messages, errors, <<>>) do
    {Enum.reverse(messages), Enum.reverse(errors)}
  end

  defp decode_line(<<>>, messages, errors, buffer) do
    error = build_error(buffer)

    {Enum.reverse(messages), Enum.reverse([error | errors])}
  end

  defp decode_line(
         <<type::unsigned-integer-size(1)-unit(8), checksum::unsigned-integer-size(4)-unit(8),
           packaged_body::binary>> = data,
         messages,
         errors,
         buffer
       )
       when type in [1, 2, 3, 4] do
    with {:ok, body, rest} <- Msgpax.unpack_slice(packaged_body),
         {:ok, message} <- to_message_type(type).parse(body) do
      message =
        struct(message,
          checksum: checksum,
          valid: :erlang.adler32(to_message_type(type).pack(message)) == checksum
        )

      decode_line(rest, [message | messages], errors, buffer)
    else
      {:error, reason} ->
        error = build_error(type, packaged_body, reason, data)
        <<skip::binary-size(1)-unit(8), rest::binary>> = data

        decode_line(
          rest,
          messages,
          [error | errors],
          <<buffer::binary, skip::binary-size(1)-unit(8)>>
        )
    end
  end

  defp decode_line(
         <<5::unsigned-integer-size(1)-unit(8), checksum::unsigned-integer-size(4)-unit(8),
           transaction_id::unsigned-integer-size(4)-unit(8),
           total_chunks::unsigned-integer-size(1)-unit(8), rest::binary>>,
         messages,
         errors,
         buffer
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

    decode_line(rest, [message | messages], errors, buffer)
  end

  defp decode_line(
         <<6::unsigned-integer-size(1)-unit(8), checksum::unsigned-integer-size(4)-unit(8),
           transaction_id::unsigned-integer-size(4)-unit(8),
           chunk_index::unsigned-integer-size(1)-unit(8),
           chunk_size::unsigned-integer-size(2)-unit(8),
           chunk_data::binary-size(chunk_size)-unit(8), rest::binary>>,
         messages,
         errors,
         buffer
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

    decode_line(rest, [message | messages], errors, buffer)
  end

  # If the line starts with a newline, we skip it and continue decoding the rest of the binary.
  defp decode_line(<<"\n", rest::binary>>, messages, errors, buffer) do
    decode_line(rest, messages, errors, buffer)
  end

  defp decode_line(<<byte_to_skip::size(1)-unit(8), rest::binary>>, messages, errors, buffer) do
    decode_line(rest, messages, errors, <<buffer::binary, byte_to_skip::size(1)-unit(8)>>)
  end

  defp build_error(type, body, reason, payload) do
    %ParseError{
      message: "Failed to parse message of type #{type}",
      reason: reason,
      data: %{type: type, body: body, payload: payload}
    }
  end

  defp build_error(payload) do
    %ParseError{
      message: "Failed to parse message for unknown type",
      reason: :unknown_type,
      data: %{payload: payload}
    }
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
