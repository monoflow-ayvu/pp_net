defmodule PPNetMemoryTest do
  use ExUnit.Case, async: true

  alias PPNet.Message.ChunkedMessageHeader
  alias PPNet.Message.Image

  @moduletag timeout: 120_000

  # 1.6 MB is the clip size from the reCamera field report (2026-07-02) where a
  # single encode_message/2 call OOM-killed a 256 MB target. Budgets are heap
  # words (8 bytes on 64-bit): list-based chunking needs 3.2M+ live words for
  # this payload, while binary-matched chunking keeps the payload bytes in refc
  # binaries outside the process heap.
  @payload_size 1_600_000
  @eager_heap_budget 1_500_000
  @stream_heap_budget 750_000

  # ceil((1_600_000 + 25 bytes of Image.pack overhead) / 232-byte chunks)
  @expected_chunks 6897

  defp large_image do
    %Image{
      id: "00000000-0000-0000-0000-000000000000",
      format: :h264,
      data: <<0, 0, 0, 1>> <> :crypto.strong_rand_bytes(@payload_size - 4),
      datetime: ~U[2026-07-02 12:00:00Z]
    }
  end

  # The VM kills the process at the first GC where the heap exceeds the cap.
  defp run_with_heap_budget(budget_words, fun) do
    parent = self()

    {pid, ref} =
      :erlang.spawn_opt(
        fn -> send(parent, {:result, self(), fun.()}) end,
        [:monitor, max_heap_size: %{size: budget_words, kill: true, error_logger: false}]
      )

    receive do
      {:result, ^pid, result} -> {:ok, result}
      {:DOWN, ^ref, :process, ^pid, :killed} -> {:error, :heap_budget_exceeded}
      {:DOWN, ^ref, :process, ^pid, reason} -> {:error, {:unexpected_exit, reason}}
    after
      100_000 -> {:error, :timeout}
    end
  end

  test "encode_message/2 of a 1.6 MB image stays within an O(payload) heap budget" do
    message = large_image()

    assert {:ok, frames} = run_with_heap_budget(@eager_heap_budget, fn -> PPNet.encode_message(message) end)

    assert length(frames) == @expected_chunks + 1

    assert %{messages: [%ChunkedMessageHeader{total_chunks: @expected_chunks} = header | chunks], errors: []} =
             frames
             |> Enum.join()
             |> PPNet.parse()

    assert {:ok, ^message} = PPNet.chunked_to_message([header | chunks])
  end

  test "encode_message_stream/2 consumed frame-by-frame stays within a small heap budget" do
    message = large_image()

    assert {:ok, {frame_count, total_bytes}} =
             run_with_heap_budget(@stream_heap_budget, fn ->
               message
               |> PPNet.encode_message_stream()
               |> Enum.reduce({0, 0}, fn frame, {count, bytes} -> {count + 1, bytes + byte_size(frame)} end)
             end)

    assert frame_count == @expected_chunks + 1
    assert total_bytes > @payload_size
  end

  test "heap budget harness detects the 0.1.5 list-based chunking blow-up" do
    # proves the budget is tight enough to catch a regression to list chunking
    packed = Image.pack(large_image())

    assert {:error, :heap_budget_exceeded} =
             run_with_heap_budget(@eager_heap_budget, fn ->
               packed
               |> :binary.bin_to_list()
               |> Enum.chunk_every(232)
               |> Enum.map(&IO.iodata_to_binary/1)
               |> length()
             end)
  end
end
