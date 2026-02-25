defmodule PpnetDemo do
  @chunk_size_limit 255

  def tcp_type_chunk(binary, chunk_size) when chunk_size <= @chunk_size_limit do
    chunk_header_type = 1
    chunk_message_type = 2
    header_size = 6
    transaction_id = transaction_id()

    chunks =
      binary
      |> :binary.bin_to_list()
      |> Enum.chunk_every(chunk_size - header_size)

    total_chunks = length(chunks)

    header_message =
      <<
        chunk_header_type::unsigned-integer-size(1)-unit(8),
        transaction_id::unsigned-integer-size(4)-unit(8),
        total_chunks::unsigned-integer-size(1)-unit(8)
      >>

    messages =
      for {chunk, index} <- Enum.with_index(chunks) do
        chunk_bin = :binary.list_to_bin(chunk)

        <<
          chunk_message_type::unsigned-integer-size(1)-unit(8),
          transaction_id::unsigned-integer-size(4)-unit(8),
          index::unsigned-integer-size(1)-unit(8),
          chunk_bin::binary
        >>
      end

    IO.puts("Binary size: #{byte_size(binary)}")
    IO.puts("Total messages: #{length(messages)} + 1 header message")
    IO.puts("Header size: #{header_size}")
    IO.puts("Chunk size: #{chunk_size}")
    IO.puts("Bynary bytes per message: #{chunk_size - header_size}")
    IO.puts("Header message size: #{byte_size(header_message)}")

    [header_message | messages]
  end

  def http(binary) do
    %{
      headers: %{
        "Content-Type" => "application/octet-stream",
        "Content-Length" => byte_size(binary),
        "X-Transaction-Id" => transaction_id()
      },
      body: binary
    }
  end

  defp transaction_id do
    <<int::unsigned-integer-size(4)-unit(8)>> = :crypto.strong_rand_bytes(4)
    int
  end
end
