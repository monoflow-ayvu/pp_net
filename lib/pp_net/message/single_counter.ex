defmodule PPNet.Message.SingleCounter do
  @moduledoc """
  This module defines the `PPNet.Message.SingleCounter` struct and provides functions to parse
  a binary or list representation of a SingleCounter message into this struct.
  """
  @behaviour PPNet.Message

  use TypedStruct

  alias PPNet.Message.SingleCounter
  alias PPNet.ParseError

  @derive Jason.Encoder
  @type_code 2

  typedstruct do
    @typedoc """
    The `PPNet.Message.SingleCounter` struct

    ## Fields

    * `kind` - The kind of the counter
    * `value` - The value of the counter
    * `pulses` - The number of pulses
    * `duration_ms` - The duration of the counter in milliseconds
    """

    field(:kind, String.t(), enforce: true)
    field(:value, any(), enforce: true)
    field(:pulses, integer(), enforce: true)
    field(:duration_ms, integer(), enforce: true)
  end

  @impl true
  def type_code, do: @type_code

  @impl true
  def pack(%__MODULE__{} = message) do
    Msgpax.pack!(
      [
        message.kind,
        message.value,
        message.pulses,
        message.duration_ms
      ],
      iodata: false
    )
  end

  @impl true
  def parse(packaged_body) when is_binary(packaged_body) do
    with {:ok, unpacked_body} <- Msgpax.unpack(packaged_body) do
      parse(unpacked_body)
    end
  end

  def parse([kind, value, pulses, duration_ms])
      when is_binary(kind) and is_integer(pulses) and is_integer(duration_ms) do
    {:ok,
     %SingleCounter{
       kind: kind,
       value: value,
       pulses: pulses,
       duration_ms: duration_ms
     }}
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
