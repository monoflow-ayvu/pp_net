defmodule PPNet.Message.OTARequest do
  @moduledoc """
  This module defines the `PPNet.Message.OTARequest` struct and provides functions to parse
  a binary representation of an OTARequest message into this struct.

  The server sends an OTARequest to the GPS to ask for a firmware update (OTA). The GPS downloads
  the firmware from `url` and checks it against `sum`, computed with the `sumtype` algorithm. The
  GPS then reports with `OTAProgress` and `OTAFinish`, both carrying the same `id`.

  ## Wire format

  | Field    | Type          | Bytes                                 |
  | -------- | ------------- | ------------------------------------- |
  | id       | binary        | 16 (UUIDv4)                           |
  | hop      | uint8         | 1                                     |
  | datetime | uint32 (Unix) | 4                                     |
  | sumtype  | uint8         | 1 (`md5` = 0, `sha256` = 1, `sha512` = 2) |
  | sum      | binary        | 16 (`md5`), 32 (`sha256`), 64 (`sha512`) |
  | url_size | uint16        | 2                                     |
  | url      | string        | url_size                              |

  `sumtype` sets the size of `sum`, so `sum` has no size field. A request with a long `url`, such as
  a presigned S3 url, is split into chunks. `parse/1` ignores the bytes after `url`, so new fields
  can be appended to the end of the body.
  """
  @behaviour PPNet.Message

  use TypedStruct

  import PPNet.Guards, only: [is_hop: 1]

  alias PPNet.PackError
  alias PPNet.ParseError

  @type_code 12
  @sumtype_codes %{md5: 0, sha256: 1, sha512: 2}
  @sumtype_codes_reverse Map.new(@sumtype_codes, fn {sumtype, code} -> {code, sumtype} end)
  @sum_sizes %{md5: 16, sha256: 32, sha512: 64}
  @max_url_size 0xFFFF
  @derive Jason.Encoder

  @type uuidv4 :: String.t()
  @type sumtype :: :md5 | :sha256 | :sha512

  typedstruct do
    @typedoc """
    The `PPNet.Message.OTARequest` struct

    ## Fields

    * `id` - UUIDv4 identifying the OTA operation; `OTAProgress` and `OTAFinish` carry it back
    * `sumtype` - Checksum algorithm: `:md5`, `:sha256` or `:sha512`
    * `sum` - Raw checksum bytes, not the hex string: 16 bytes for `:md5`, 32 for `:sha256` and
      64 for `:sha512`
    * `url` - Firmware download address, a non-empty UTF-8 string of at most 65 535 bytes
    * `datetime` - Timestamp of the request
    * `hop` - Unsigned 8-bit integer (0–255): the address of the device on the board's internal bus
      that must apply the update; 0 (the default) is the board itself
    """

    field(:id, uuidv4(), enforce: true)
    field(:sumtype, sumtype(), enforce: true)
    field(:sum, binary(), enforce: true)
    field(:url, String.t(), enforce: true)
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

  def pack(%__MODULE__{sumtype: sumtype, sum: sum, url: url} = message) do
    with :ok <- validate_sumtype(sumtype),
         :ok <- validate_sum(sumtype, sum),
         :ok <- validate_url(url) do
      pack_request(message)
    end
  end

  def pack(_message) do
    {:error, %PackError{message: "Invalid struct provided to pack/1", reason: :invalid_struct}}
  end

  defp validate_sumtype(sumtype) when is_map_key(@sumtype_codes, sumtype), do: :ok

  defp validate_sumtype(_sumtype) do
    {:error, %PackError{message: "sumtype must be :md5, :sha256 or :sha512", reason: :invalid_sumtype}}
  end

  defp validate_sum(sumtype, sum) when is_binary(sum) and byte_size(sum) == :erlang.map_get(sumtype, @sum_sizes),
    do: :ok

  defp validate_sum(sumtype, _sum) do
    {:error,
     %PackError{
       message: "sum must be the #{@sum_sizes[sumtype]} raw bytes of a #{sumtype} checksum",
       reason: :invalid_sum
     }}
  end

  defp validate_url(url) when is_binary(url) and byte_size(url) > 0 and byte_size(url) <= @max_url_size do
    if String.valid?(url), do: :ok, else: invalid_url()
  end

  defp validate_url(_url), do: invalid_url()

  defp invalid_url do
    {:error,
     %PackError{
       message: "url must be a non-empty UTF-8 string of at most #{@max_url_size} bytes",
       reason: :invalid_url
     }}
  end

  defp pack_request(%__MODULE__{
         id: id,
         hop: hop,
         sumtype: sumtype,
         sum: sum,
         url: url,
         datetime: %DateTime{} = datetime
       })
       when is_binary(id) do
    sum_size = @sum_sizes[sumtype]
    url_size = byte_size(url)

    {:ok,
     <<
       UUID.string_to_binary!(id)::binary-size(16)-unit(8),
       hop::unsigned-integer-size(1)-unit(8),
       DateTime.to_unix(datetime)::unsigned-integer-size(4)-unit(8),
       @sumtype_codes[sumtype]::unsigned-integer-size(1)-unit(8),
       sum::binary-size(sum_size)-unit(8),
       url_size::unsigned-integer-size(2)-unit(8),
       url::binary-size(url_size)-unit(8)
     >>}
  rescue
    error ->
      {:error, %PackError{message: "Invalid struct provided to pack/1", reason: {error, __STACKTRACE__}}}
  end

  defp pack_request(_message) do
    {:error, %PackError{message: "Invalid struct provided to pack/1", reason: :invalid_struct}}
  end

  @impl true
  def parse(payload)

  def parse(
        <<id::binary-size(16)-unit(8), hop::unsigned-integer-size(1)-unit(8),
          datetime::unsigned-integer-size(4)-unit(8), sumtype_code::unsigned-integer-size(1)-unit(8),
          sum_and_url::binary>> = payload
      )
      when is_map_key(@sumtype_codes_reverse, sumtype_code) do
    sumtype = @sumtype_codes_reverse[sumtype_code]
    sum_size = @sum_sizes[sumtype]

    case sum_and_url do
      <<sum::binary-size(sum_size)-unit(8), url_size::unsigned-integer-size(2)-unit(8),
        url::binary-size(url_size)-unit(8), _future_fields::binary>> ->
        {:ok,
         %__MODULE__{
           id: UUID.binary_to_string!(id),
           hop: hop,
           sumtype: sumtype,
           sum: sum,
           url: url,
           datetime: DateTime.from_unix!(datetime)
         }}

      _truncated ->
        unknown_format(payload)
    end
  end

  def parse(data), do: unknown_format(data)

  defp unknown_format(data) do
    {:error,
     %ParseError{
       message: "The message body does not match the expected format",
       reason: :unknown_format,
       data: %{payload: data}
     }}
  end
end
