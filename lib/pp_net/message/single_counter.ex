defmodule PPNet.Message.SingleCounter do
  @moduledoc """
  This module defines the `PPNet.Message.SingleCounter` struct and provides functions to parse
  a binary or list representation of a SingleCounter message into this struct.
  """
  @behaviour PPNet.Message

  use TypedStruct

  alias PPNet.Message.SingleCounter
  alias PPNet.PackError
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
    * `datetime` - The timestamp when the counter message was sent
    * `hop` - Unsigned 8-bit integer (0–255): the address of the device on the board's internal bus
      that generated the counter; 0 (the default) is the board itself
    """

    field(:kind, String.t(), enforce: true)
    field(:value, any(), enforce: true)
    field(:pulses, integer(), enforce: true)
    field(:duration_ms, integer(), enforce: true)
    field(:datetime, DateTime.t(), enforce: true)
    field(:hop, 0..255, default: 0)
  end

  defguardp is_hop(hop) when is_integer(hop) and hop >= 0 and hop <= 255

  @impl true
  def type_code, do: @type_code

  @impl true
  def datetime(%__MODULE__{datetime: datetime}), do: datetime

  @impl true
  def pack(%__MODULE__{hop: hop}) when not is_hop(hop), do: PackError.invalid_hop()

  def pack(%__MODULE__{
        kind: kind,
        value: value,
        pulses: pulses,
        duration_ms: duration_ms,
        datetime: %DateTime{} = datetime,
        hop: hop
      })
      when is_binary(kind) and is_integer(pulses) and is_integer(duration_ms) do
    {:ok,
     Msgpax.pack!(
       [
         kind,
         value,
         pulses,
         duration_ms,
         DateTime.to_unix(datetime),
         hop
       ],
       iodata: false
     )}
  rescue
    error ->
      {:error, %PackError{message: "Invalid struct provided to pack/1", reason: {error, __STACKTRACE__}}}
  end

  def pack(_message) do
    {:error, %PackError{message: "Invalid struct provided to pack/1", reason: :invalid_struct}}
  end

  @impl true
  def parse(packaged_body) when is_binary(packaged_body) do
    with {:ok, unpacked_body} <- Msgpax.unpack(packaged_body) do
      parse(unpacked_body)
    end
  end

  # credo:disable-for-lines:2
  def parse([kind, value, pulses, duration_ms, datetime, hop])
      when is_binary(kind) and is_integer(pulses) and is_integer(duration_ms) and is_integer(datetime) and is_hop(hop) do
    {:ok,
     %SingleCounter{
       kind: kind,
       value: value,
       pulses: pulses,
       duration_ms: duration_ms,
       datetime: DateTime.from_unix!(datetime),
       hop: hop
     }}
  end

  def parse([kind, value, pulses, duration_ms, datetime])
      when is_binary(kind) and is_integer(pulses) and is_integer(duration_ms) and is_integer(datetime) do
    {:ok,
     %SingleCounter{
       kind: kind,
       value: value,
       pulses: pulses,
       duration_ms: duration_ms,
       datetime: DateTime.from_unix!(datetime),
       hop: 0
     }}
  end

  def parse([kind, value, pulses, duration_ms])
      when is_binary(kind) and is_integer(pulses) and is_integer(duration_ms) do
    {:ok,
     %SingleCounter{
       kind: kind,
       value: value,
       pulses: pulses,
       duration_ms: duration_ms,
       datetime: nil,
       hop: 0
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
