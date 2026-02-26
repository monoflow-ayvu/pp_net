defmodule PPNet.Message.Ping do
  @moduledoc """
  This module defines the `PPNet.Message.Ping` struct and provides functions to parse
  a binary or list representation of a Ping message into this struct.
  """
  use TypedStruct

  alias PPNet.Message.Ping
  alias PPNet.ParseError

  @derive Jason.Encoder
  @type_code 3

  typedstruct do
    @typedoc """
    The `PPNet.Message.Ping` struct
    """
    field(:temperature, float(), enforce: true)
    field(:uptime_ms, integer(), enforce: true)
    field(:extra, map(), default: %{})
    field(:checksum, integer())
    field(:valid, boolean())
  end

  def type_code, do: @type_code

  def pack(%__MODULE__{extra: extra} = message) when is_map(extra) do
    Msgpax.pack!(
      [message.temperature, message.uptime_ms, extra],
      iodata: false
    )
  end

  def pack(%__MODULE__{} = message) do
    Msgpax.pack!(
      [message.temperature, message.uptime_ms],
      iodata: false
    )
  end

  def parse(packaged_body) when is_binary(packaged_body) do
    with {:ok, unpacked_body} <- Msgpax.unpack(packaged_body) do
      parse(unpacked_body)
    end
  end

  def parse([temperature, uptime_ms, extra])
      when is_float(temperature) and is_integer(uptime_ms) and is_map(extra) do
    {:ok, %Ping{temperature: temperature, uptime_ms: uptime_ms, extra: extra}}
  end

  def parse([temperature, uptime_ms]) when is_float(temperature) and is_integer(uptime_ms) do
    {:ok, %Ping{temperature: temperature, uptime_ms: uptime_ms, extra: %{}}}
  end

  def parse(unpacked_body) when is_list(unpacked_body) do
    {:error,
     %ParseError{
       message: "The message body does not match the expected format",
       reason: :unknown_format,
       data: {:unpacked_body, unpacked_body}
     }}
  end
end
