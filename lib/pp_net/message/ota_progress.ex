defmodule PPNet.Message.OTAProgress do
  @moduledoc """
  This module defines the `PPNet.Message.OTAProgress` struct and provides functions to parse
  a binary representation of an OTAProgress message into this struct.

  The GPS sends an OTAProgress to the server to report how far a firmware update requested by an
  `OTARequest` has gone.

  ## Wire format

  | Field    | Type          | Bytes       |
  | -------- | ------------- | ----------- |
  | id       | binary        | 16 (UUIDv4) |
  | hop      | uint8         | 1           |
  | progress | uint8         | 1           |
  | datetime | uint32 (Unix) | 4           |

  `parse/1` ignores the bytes after `datetime`, so new fields can be appended to the end of the
  body.
  """
  @behaviour PPNet.Message

  use TypedStruct

  import PPNet.Guards, only: [is_hop: 1]

  alias PPNet.PackError
  alias PPNet.ParseError

  @type_code 13
  @max_progress 100
  @derive Jason.Encoder

  @type uuidv4 :: String.t()

  typedstruct do
    @typedoc """
    The `PPNet.Message.OTAProgress` struct

    ## Fields

    * `id` - UUIDv4 of the `OTARequest` this progress refers to
    * `progress` - Percentage of the update already done, an integer from 0 to 100
    * `datetime` - Timestamp of the progress report
    * `hop` - Unsigned 8-bit integer (0–255): the address of the device on the board's internal bus
      that reports the progress; 0 (the default) is the board itself
    """

    field(:id, uuidv4(), enforce: true)
    field(:progress, 0..100, enforce: true)
    field(:datetime, DateTime.t(), enforce: true)
    field(:hop, 0..255, default: 0)
  end

  @impl true
  def type_code, do: @type_code

  @impl true
  def datetime(%__MODULE__{datetime: datetime}), do: datetime

  @impl true
  def pack(message)

  def pack(%__MODULE__{hop: hop}) when not is_hop(hop), do: PackError.invalid_hop()

  def pack(%__MODULE__{progress: progress}) when progress not in 0..@max_progress, do: invalid_progress()

  def pack(%__MODULE__{id: id, hop: hop, progress: progress, datetime: %DateTime{} = datetime}) when is_binary(id) do
    {:ok,
     <<
       UUID.string_to_binary!(id)::binary-size(16)-unit(8),
       hop::unsigned-integer-size(1)-unit(8),
       progress::unsigned-integer-size(1)-unit(8),
       DateTime.to_unix(datetime)::unsigned-integer-size(4)-unit(8)
     >>}
  rescue
    error ->
      {:error, %PackError{message: "Invalid struct provided to pack/1", reason: {error, __STACKTRACE__}}}
  end

  def pack(_message) do
    {:error, %PackError{message: "Invalid struct provided to pack/1", reason: :invalid_struct}}
  end

  defp invalid_progress do
    {:error,
     %PackError{
       message: "progress must be an integer between 0 and #{@max_progress}",
       reason: :invalid_progress
     }}
  end

  @impl true
  def parse(payload)

  def parse(
        <<id::binary-size(16)-unit(8), hop::unsigned-integer-size(1)-unit(8),
          progress::unsigned-integer-size(1)-unit(8), datetime::unsigned-integer-size(4)-unit(8),
          _future_fields::binary>>
      )
      when progress <= @max_progress do
    {:ok,
     %__MODULE__{
       id: UUID.binary_to_string!(id),
       hop: hop,
       progress: progress,
       datetime: DateTime.from_unix!(datetime)
     }}
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
