defmodule PPNet.Message.OTAFinish do
  @moduledoc """
  This module defines the `PPNet.Message.OTAFinish` struct and provides functions to parse
  a binary representation of an OTAFinish message into this struct.

  The GPS sends an OTAFinish to the server when a firmware update requested by an `OTARequest`
  ends, with its result.

  ## Wire format

  | Field              | Type          | Bytes              |
  | ------------------ | ------------- | ------------------ |
  | id                 | binary        | 16 (UUIDv4)        |
  | hop                | uint8         | 1                  |
  | success            | uint8         | 1 (0 or 1)         |
  | datetime           | uint32 (Unix) | 4                  |
  | error_message_size | uint8         | 1                  |
  | error_message      | string        | error_message_size |

  An OTAFinish always fits in a single frame and is never chunked: `error_message` may use only the
  bytes the frame has left after the fixed fields (220 bytes with the default limit of 254). A `nil`
  or empty `error_message` is sent as `error_message_size` 0 and parsed back as `nil`. `parse/1`
  ignores the bytes after `error_message`, so new fields can be appended to the end of the body.
  """
  @behaviour PPNet.Message

  use TypedStruct

  import PPNet.Guards, only: [is_hop: 1]

  alias PPNet.PackError
  alias PPNet.ParseError

  @type_code 14
  @default_limit 254
  @frame_overhead PPNet.frame_overhead()
  # id (16) + hop (1) + success (1) + datetime (4) + error_message_size (1)
  @fixed_fields_size 23
  @derive Jason.Encoder

  @type uuidv4 :: String.t()

  typedstruct do
    @typedoc """
    The `PPNet.Message.OTAFinish` struct

    ## Fields

    * `id` - UUIDv4 of the `OTARequest` this result refers to
    * `success` - `true` when the update was applied, `false` when it failed
    * `error_message` - Reason of the failure, a UTF-8 string that fits in what is left of the frame
      (220 bytes with the default limit of 254). Defaults to `nil`
    * `datetime` - Timestamp of the end of the update
    * `hop` - Unsigned 8-bit integer (0–255): the address of the device on the board's internal bus
      that reports the result; 0 (the default) is the board itself
    """

    field(:id, uuidv4(), enforce: true)
    field(:success, boolean(), enforce: true)
    field(:error_message, String.t() | nil, default: nil)
    field(:datetime, DateTime.t(), enforce: true)
    field(:hop, 0..255, default: 0)
  end

  @impl true
  def type_code, do: @type_code

  @impl true
  def datetime(%__MODULE__{datetime: datetime}), do: datetime

  @impl true
  def pack(message)

  def pack(message), do: pack(message, nil)

  @impl true
  def pack(message, limit)

  def pack(%__MODULE__{hop: hop}, _limit) when not is_hop(hop), do: PackError.invalid_hop()

  def pack(%__MODULE__{success: success}, _limit) when not is_boolean(success), do: invalid_success()

  def pack(%__MODULE__{error_message: error_message}, _limit)
      when error_message != nil and not is_binary(error_message), do: invalid_error_message(error_message)

  def pack(%__MODULE__{id: id, success: success, datetime: %DateTime{} = datetime, hop: hop} = message, limit)
      when is_binary(id) do
    error_message = message.error_message || ""
    error_message_size = byte_size(error_message)
    max_size = max_error_message_size(limit)

    if String.valid?(error_message) and (error_message_size == 0 or error_message_size <= max_size) do
      {:ok,
       <<
         UUID.string_to_binary!(id)::binary-size(16)-unit(8),
         hop::unsigned-integer-size(1)-unit(8),
         success_code(success)::unsigned-integer-size(1)-unit(8),
         DateTime.to_unix(datetime)::unsigned-integer-size(4)-unit(8),
         error_message_size::unsigned-integer-size(1)-unit(8),
         error_message::binary-size(error_message_size)-unit(8)
       >>}
    else
      invalid_error_message(%{size: error_message_size, max_size: max_size, limit: limit})
    end
  rescue
    error ->
      {:error, %PackError{message: "Invalid struct provided to pack/1", reason: {error, __STACKTRACE__}}}
  end

  def pack(_message, _limit) do
    {:error, %PackError{message: "Invalid struct provided to pack/1", reason: :invalid_struct}}
  end

  # what is left of the frame after the overhead and the fixed fields
  defp max_error_message_size(nil), do: max_error_message_size(@default_limit)
  defp max_error_message_size(limit), do: limit - @frame_overhead - @fixed_fields_size

  defp success_code(true), do: 1
  defp success_code(false), do: 0

  defp invalid_success do
    {:error, %PackError{message: "success must be a boolean", reason: :invalid_success}}
  end

  defp invalid_error_message(data) do
    {:error,
     %PackError{
       message: "error_message must be nil or a UTF-8 string that fits in the frame",
       reason: :invalid_error_message,
       data: data
     }}
  end

  @impl true
  def parse(payload)

  def parse(
        <<id::binary-size(16)-unit(8), hop::unsigned-integer-size(1)-unit(8), success::unsigned-integer-size(1)-unit(8),
          datetime::unsigned-integer-size(4)-unit(8), error_message_size::unsigned-integer-size(1)-unit(8),
          error_message::binary-size(error_message_size)-unit(8), _future_fields::binary>>
      )
      when success in [0, 1] do
    {:ok,
     %__MODULE__{
       id: UUID.binary_to_string!(id),
       hop: hop,
       success: success == 1,
       error_message: if(error_message != "", do: error_message),
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
