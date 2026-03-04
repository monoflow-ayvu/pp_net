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
  @format_to_code %{jpeg: 1, webp: 2, png: 3}
  @code_to_format Map.new(@format_to_code, fn {k, v} -> {v, k} end)

  @type uuidv4 :: String.t()

  typedstruct do
    field(:id, uuidv4(), enforce: true)
    field(:format, format(), enforce: true)
    field(:data, binary(), enforce: true)
  end

  @impl true
  def type_code, do: @type_code

  @impl true
  def pack(%__MODULE__{} = message) do
    <<
      UUID.string_to_binary!(message.id)::binary-size(16)-unit(8),
      @format_to_code[message.format]::unsigned-integer-size(1)-unit(8),
      message.data::binary-size(byte_size(message.data))-unit(8)
    >>
  end

  @impl true
  def parse(<<id::binary-size(16)-unit(8), format_code::unsigned-integer-size(1)-unit(8), data::binary>>) do
    {:ok, %__MODULE__{id: UUID.binary_to_string!(id), data: data, format: @code_to_format[format_code]}}
  end

  def parse(data) do
    {:error,
     %ParseError{
       message: "The message body does not match the expected format",
       reason: :unknown_format,
       data: %{payload: data}
     }}
  end
end
