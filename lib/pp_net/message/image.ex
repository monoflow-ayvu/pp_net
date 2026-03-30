defmodule PPNet.Message.Image do
  @moduledoc """
  This module defines the `PPNet.Message.Image` struct and provides functions to parse
  a binary or list representation of an Image message into this struct.
  """
  @behaviour PPNet.Message

  use TypedStruct

  alias PPNet.PackError
  alias PPNet.ParseError

  @type_code 5
  @derive Jason.Encoder

  @type format :: :jpeg | :webp | :png
  @format_to_code %{jpeg: 1, webp: 2, png: 3}
  @code_to_format Map.new(@format_to_code, fn {k, v} -> {v, k} end)
  @valid_formats Map.keys(@format_to_code)
  @type uuidv4 :: String.t()

  typedstruct do
    @typedoc """
    The `PPNet.Message.Image` struct

    ## Fields

    * `id` - UUIDv4 identifying the image
    * `format` - Image format (`:jpeg`, `:webp`, or `:png`)
    * `data` - Raw image binary
    * `datetime` - Timestamp of the image capture
    """

    field(:id, uuidv4(), enforce: true)
    field(:format, format(), enforce: true)
    field(:data, binary(), enforce: true)
    field(:datetime, DateTime.t(), enforce: true)
  end

  @impl true
  def type_code, do: @type_code

  @impl true
  def datetime(%__MODULE__{datetime: datetime}), do: datetime

  @impl true
  def pack(%__MODULE__{id: id, format: format, data: data, datetime: %DateTime{} = datetime})
      when is_binary(id) and format in @valid_formats and is_binary(data) do
    data_size = byte_size(data)

    <<
      UUID.string_to_binary!(id)::binary-size(16)-unit(8),
      @format_to_code[format]::unsigned-integer-size(1)-unit(8),
      DateTime.to_unix(datetime)::unsigned-integer-size(4)-unit(8),
      data_size::unsigned-integer-size(4)-unit(8),
      data::binary-size(data_size)-unit(8)
    >>
  rescue
    error ->
      {:error, %PackError{message: "Invalid struct provided to pack/1", reason: {error, __STACKTRACE__}}}
  end

  def pack(_message) do
    {:error, %PackError{message: "Invalid struct provided to pack/1", reason: :invalid_struct}}
  end

  @impl true
  def parse(
        <<id::binary-size(16)-unit(8), format_code::unsigned-integer-size(1)-unit(8),
          datetime::unsigned-integer-size(4)-unit(8), data_size::unsigned-integer-size(4)-unit(8),
          data::binary-size(data_size)-unit(8)>>
      ) do
    {:ok,
     %__MODULE__{
       id: UUID.binary_to_string!(id),
       data: data,
       format: @code_to_format[format_code],
       datetime: DateTime.from_unix!(datetime)
     }}
  end

  @impl true
  def parse(<<id::binary-size(16)-unit(8), format_code::unsigned-integer-size(1)-unit(8), data::binary>>) do
    {:ok, %__MODULE__{id: UUID.binary_to_string!(id), data: data, format: @code_to_format[format_code], datetime: nil}}
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
