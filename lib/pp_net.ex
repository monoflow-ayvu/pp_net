defmodule PPNet do
  @moduledoc """
  This module defines the `PPNet` module, which provides functions to parse
  a binary or list representation of a message into a struct.
  """
  alias PPNet.Message.Hello
  alias PPNet.Message.ImageBody
  alias PPNet.Message.ImageHeader
  alias PPNet.Message.SingleCounter
  alias PPNet.ParseError

  def run do
    %Hello{
      unique_id: "TestRunner",
      board_identifier: "Tester",
      version: 1,
      board_version: 1,
      boot_id: 1,
      ppnet_version: 1
    }
    |> encode_message(:raw)
    |> dbg()
  end

  def encode_message(%module{} = message, target) when module in [Hello, SingleCounter] do
    packaged_data = module.pack(message)

    total_size = 1 + 4 + byte_size(packaged_data)
    valid_total_size(target, total_size)

    checksum = :erlang.adler32(packaged_data)

    <<
      module.type_code()::unsigned-integer-size(1)-unit(8),
      checksum::32-big-unsigned-integer,
      packaged_data::binary
    >>
  end

  def encode_image(binary, chunk_size, target) do
    valid_total_size(target, chunk_size)

    chunk_header_size = 6
    transaction_id = transaction_id()

    chunks =
      binary
      |> :binary.bin_to_list()
      |> Enum.chunk_every(chunk_size - chunk_header_size)

    total_chunks = length(chunks)

    header =
      <<ImageHeader.type_code()::unsigned-integer-size(1)-unit(8)>> <>
        ImageHeader.pack(%ImageHeader{
          transaction_id: transaction_id,
          total_chunks: total_chunks
        })

    messages =
      for {chunk, index} <- Enum.with_index(chunks) do
        <<ImageBody.type_code()::unsigned-integer-size(1)-unit(8)>> <>
          ImageBody.pack(%ImageBody{
            transaction_id: transaction_id,
            chunk_index: index,
            chunk_data: :binary.list_to_bin(chunk)
          })
      end

    [header | messages]
  end

  @doc """
  Parses a binary or list representation of a message into a struct.
  """
  @spec parse(binary() | list(integer())) ::
          {:ok, Hello.t() | SingleCounter.t()} | {:error, ParseError.t()}

  def parse(data) when is_list(data), do: parse(IO.iodata_to_binary(data))

  def parse(
        <<type::unsigned-integer-size(1)-unit(8), checksum::unsigned-integer-size(4)-unit(8),
          packaged_body::binary>> =
          data
      )
      when type in [1, 2] do
    case to_message_type(type).parse(packaged_body) do
      {:ok, body} ->
        {:ok, struct(body, checksum: checksum, valid: :erlang.adler32(packaged_body) == checksum)}

      {:error, reason} ->
        {:error,
         %ParseError{
           message: "Unable to decode message body for type #{to_message_type(type)}",
           reason: reason,
           data: data
         }}
    end
  end

  def parse(
        <<3::unsigned-integer-size(1)-unit(8), transaction_id::unsigned-integer-size(4)-unit(8),
          total_chunks::unsigned-integer-size(1)-unit(8)>>
      ) do
    {:ok, %ImageHeader{transaction_id: transaction_id, total_chunks: total_chunks}}
  end

  def parse(
        <<4::unsigned-integer-size(1)-unit(8), transaction_id::unsigned-integer-size(4)-unit(8),
          chunk_index::unsigned-integer-size(1)-unit(8), chunk_data::binary>>
      ) do
    {:ok,
     %ImageBody{transaction_id: transaction_id, chunk_index: chunk_index, chunk_data: chunk_data}}
  end

  def parse(data) do
    {:error,
     %ParseError{
       message: "Unknown message format",
       reason: :unknown_format,
       data: data
     }}
  end

  defp to_message_type(1), do: Hello
  defp to_message_type(2), do: SingleCounter

  defp valid_total_size(:raw, total_size) when total_size > 255,
    do: raise("Total size must be less than 255")

  defp valid_total_size(:suntech, total_size) when total_size > 255,
    do: raise("Total size must be less than 255")

  defp valid_total_size(:aovx, total_size) when total_size > 200,
    do: raise("Total size must be less than 200")

  defp valid_total_size(_, _), do: :ok

  defp transaction_id do
    <<int::unsigned-integer-size(4)-unit(8)>> = :crypto.strong_rand_bytes(4)
    int
  end
end
