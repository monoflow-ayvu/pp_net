defmodule PPNet.Message.Document do
  @moduledoc """
  This module defines the `PPNet.Message.Document` struct and provides functions to parse
  a binary representation of a Document message into this struct.

  A Document carries a file of any format, identified by its MIME type (`mime`) instead of a
  fixed enum.

  ## Wire format

  | Field         | Type          | Bytes         |
  | ------------- | ------------- | ------------- |
  | id            | binary        | 16 (UUIDv4)   |
  | mime_size     | uint8         | 1             |
  | mime          | string        | mime_size     |
  | hop           | uint8         | 1             |
  | datetime      | uint32 (Unix) | 4             |
  | data_size     | uint32        | 4             |
  | data          | binary        | data_size     |
  | metadata_size | uint16        | 2             |
  | metadata      | MessagePack   | metadata_size |

  An empty `metadata` is sent as `metadata_size` 0 with no bytes. `parse/1` ignores the bytes
  after `metadata`, so new fields can be appended to the end of the body.
  """
  @behaviour PPNet.Message

  use TypedStruct

  import PPNet.Guards, only: [is_hop: 1]

  alias PPNet.PackError
  alias PPNet.ParseError

  @type_code 11
  @max_mime_size 255
  @max_metadata_size 0xFFFF
  @derive Jason.Encoder

  @type uuidv4 :: String.t()

  typedstruct do
    @typedoc """
    The `PPNet.Message.Document` struct

    ## Fields

    * `id` - UUIDv4 identifying the document
    * `mime` - MIME type of `data`, for example `"text/plain"` or `"application/pdf"`. A non-empty
      UTF-8 string of at most 255 bytes
    * `data` - Raw file binary
    * `datetime` - Timestamp of the document creation
    * `hop` - Unsigned 8-bit integer (0–255): the address of the device on the board's internal bus
      that created the document; 0 (the default) is the board itself
    * `metadata` - Free key/value map, serialized as MessagePack (at most 65 535 bytes once
      serialized). Values may be strings, numbers, booleans, `nil`, lists and nested maps. Atom keys
      and values are sent as strings, so they come back as strings after `parse/1`. Defaults to `%{}`
    """

    field(:id, uuidv4(), enforce: true)
    field(:mime, String.t(), enforce: true)
    field(:data, binary(), enforce: true)
    field(:datetime, DateTime.t(), enforce: true)
    field(:hop, 0..255, default: 0)
    field(:metadata, map(), default: %{})
  end

  @impl true
  def type_code, do: @type_code

  @impl true
  def datetime(%__MODULE__{datetime: datetime}), do: datetime

  @impl true
  def pack(message)

  def pack(%__MODULE__{hop: hop}) when not is_hop(hop), do: PackError.invalid_hop()

  def pack(%__MODULE__{mime: mime} = message) do
    with :ok <- validate_mime(mime),
         {:ok, metadata} <- pack_metadata(message.metadata) do
      pack_document(message, metadata)
    end
  end

  def pack(_message) do
    {:error, %PackError{message: "Invalid struct provided to pack/1", reason: :invalid_struct}}
  end

  defp validate_mime(mime) when is_binary(mime) and byte_size(mime) > 0 and byte_size(mime) <= @max_mime_size do
    if String.valid?(mime), do: :ok, else: invalid_mime()
  end

  defp validate_mime(_mime), do: invalid_mime()

  defp pack_metadata(metadata) when metadata == %{}, do: {:ok, <<>>}

  defp pack_metadata(metadata) when is_map(metadata) do
    case Msgpax.pack(metadata, iodata: false) do
      {:ok, packed} when byte_size(packed) <= @max_metadata_size -> {:ok, packed}
      {:ok, packed} -> invalid_metadata({:too_large, byte_size(packed)})
      {:error, error} -> invalid_metadata(error)
    end
  end

  defp pack_metadata(metadata), do: invalid_metadata(metadata)

  defp pack_document(%__MODULE__{id: id, mime: mime, data: data, datetime: %DateTime{} = datetime, hop: hop}, metadata)
       when is_binary(id) and is_binary(data) do
    mime_size = byte_size(mime)
    data_size = byte_size(data)
    metadata_size = byte_size(metadata)

    {:ok,
     <<
       UUID.string_to_binary!(id)::binary-size(16)-unit(8),
       mime_size::unsigned-integer-size(1)-unit(8),
       mime::binary-size(mime_size)-unit(8),
       hop::unsigned-integer-size(1)-unit(8),
       DateTime.to_unix(datetime)::unsigned-integer-size(4)-unit(8),
       data_size::unsigned-integer-size(4)-unit(8),
       data::binary-size(data_size)-unit(8),
       metadata_size::unsigned-integer-size(2)-unit(8),
       metadata::binary-size(metadata_size)-unit(8)
     >>}
  rescue
    error ->
      {:error, %PackError{message: "Invalid struct provided to pack/1", reason: {error, __STACKTRACE__}}}
  end

  defp pack_document(_message, _metadata) do
    {:error, %PackError{message: "Invalid struct provided to pack/1", reason: :invalid_struct}}
  end

  defp invalid_mime do
    {:error,
     %PackError{
       message: "mime must be a non-empty UTF-8 string of at most #{@max_mime_size} bytes",
       reason: :invalid_mime
     }}
  end

  defp invalid_metadata(data) do
    {:error,
     %PackError{
       message: "metadata must be a map serializable to MessagePack in at most #{@max_metadata_size} bytes",
       reason: :invalid_metadata,
       data: data
     }}
  end

  @impl true
  def parse(payload)

  def parse(
        <<id::binary-size(16)-unit(8), mime_size::unsigned-integer-size(1)-unit(8),
          mime::binary-size(mime_size)-unit(8), hop::unsigned-integer-size(1)-unit(8),
          datetime::unsigned-integer-size(4)-unit(8), data_size::unsigned-integer-size(4)-unit(8),
          data::binary-size(data_size)-unit(8), metadata_size::unsigned-integer-size(2)-unit(8),
          metadata::binary-size(metadata_size)-unit(8), _future_fields::binary>> = payload
      ) do
    case parse_metadata(metadata) do
      {:ok, metadata} ->
        {:ok,
         %__MODULE__{
           id: UUID.binary_to_string!(id),
           mime: mime,
           data: data,
           datetime: DateTime.from_unix!(datetime),
           hop: hop,
           metadata: metadata
         }}

      :error ->
        {:error,
         %ParseError{
           message: "The document metadata is not a MessagePack map",
           reason: :invalid_metadata,
           data: %{payload: payload}
         }}
    end
  end

  def parse(data) do
    {:error,
     %ParseError{
       message: "The message body does not match the expected format",
       reason: :unknown_format,
       data: %{payload: data}
     }}
  end

  defp parse_metadata(<<>>), do: {:ok, %{}}

  defp parse_metadata(binary) do
    case Msgpax.unpack(binary) do
      {:ok, metadata} when is_map(metadata) -> {:ok, metadata}
      _other -> :error
    end
  end
end
