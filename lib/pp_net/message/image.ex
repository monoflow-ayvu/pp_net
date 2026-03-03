defmodule PPNet.Message.Image do
  @moduledoc """
  This module defines the `PPNet.Message.Image` struct and provides functions to parse
  a binary or list representation of an Image message into this struct.
  """
  @behaviour PPNet.Message

  use TypedStruct

  alias PPNet.ParseError

  @type_code 5

  @type format :: :jpeg | :webp | :png

  typedstruct do
    field(:format, format(), enforce: true)
    field(:data, binary(), enforce: true)
  end

  @impl true
  def type_code, do: @type_code

  @impl true
  def pack(%__MODULE__{} = message) do
    <<
      format_to_code(message.format)::unsigned-integer-size(1)-unit(8),
      message.data::binary-size(byte_size(message.data))-unit(8)
    >>
  end

  @impl true
  def parse(<<format_code::unsigned-integer-size(1)-unit(8), data::binary>>) do
    {:ok, %__MODULE__{data: data, format: code_to_format(format_code)}}
  end

  def parse(data) do
    {:error,
     %ParseError{
       message: "The message body does not match the expected format",
       reason: :unknown_format,
       data: %{payload: data}
     }}
  end

  defp format_to_code(:jpeg), do: 1
  defp format_to_code(:webp), do: 2
  defp format_to_code(:png), do: 3
  defp code_to_format(1), do: :jpeg
  defp code_to_format(2), do: :webp
  defp code_to_format(3), do: :png
end
