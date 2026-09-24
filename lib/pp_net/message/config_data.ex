defmodule PPNet.Message.ConfigData do
  @moduledoc """
  This module defines the `PPNet.Message.ConfigData` struct and provides functions to parse
  a binary representation of a ConfigData message into this struct.

  Generic bidirectional envelope for board configuration: `kind: :schema | :full_report |
  :partial_report` is sent board → server, while `kind: :request_schema |
  :request_full_config | :request_partial_config | :set_config` is sent server → board.
  `request_payload` is the payload as a plain Elixir term (a map, a list, or `nil`) — a config
  document, a JSON Schema, a list of JSON Pointers, or a `:set_config` envelope, depending on
  `kind`. Unlike other `PPNet.Message` implementations,
  `pack/1` validates `request_payload`'s shape against `kind` (see `validate_format!/2`) and
  serializes it per `format` (`:json` or `:msgpack`) before compressing (`compression`);
  `parse/1` reverses both steps. See `CONTRACT.md` at the repo root for the full shape of
  `request_payload` per `kind`.
  """
  @behaviour PPNet.Message

  use TypedStruct

  alias PPNet.PackError
  alias PPNet.ParseError

  @device_kind_codes %{
    schema: 0,
    full_report: 1,
    partial_report: 2
  }
  @server_kind_codes %{
    request_schema: 3,
    request_full_config: 4,
    request_partial_config: 5,
    set_config: 6
  }
  @kind_codes Map.merge(@device_kind_codes, @server_kind_codes)
  @kind_codes_reverse Map.new(@kind_codes, fn {k, v} -> {v, k} end)
  @data_format_codes %{json: 0, msgpack: 1}
  @data_format_codes_reverse Map.new(@data_format_codes, fn {k, v} -> {v, k} end)
  @compression_type_codes %{none: 0, brotli: 1}
  @compression_type_codes_reverse Map.new(@compression_type_codes, fn {k, v} -> {v, k} end)

  @kinds Map.keys(@kind_codes)
  @data_formats Map.keys(@data_format_codes)
  @compression_types Map.keys(@compression_type_codes)

  @json_patch_schema __DIR__
                     |> Path.join("/config_data/json_patch_schema.json")
                     |> File.read!()
                     |> Jason.decode!()
                     |> JSV.build!()

  @type_code 9

  @derive Jason.Encoder
  typedstruct do
    @typedoc """
    The `PPNet.Message.ConfigData` struct

    Used to send and receive configuration data.

    ## Fields

    * `kind` - Identifies what is being transmitted.
    * `request_id` - Unique identifier of the message.
    * `format` - Format of the data (JSON or MsgPack).
    * `compression` - Compression of the data (none or Brotli).
    * `request_payload` - The payload as a plain Elixir term (map, list, or `nil`) — shape
      depends on `kind`, see `CONTRACT.md`.
    * `datetime` - Date and time of the transmission.
    """
    field(:kind, atom(), enforce: true)
    field(:request_id, non_neg_integer(), enforce: true)
    field(:format, atom(), enforce: true)
    field(:compression, atom(), enforce: true)
    field(:request_payload, map() | list() | nil, enforce: true)
    field(:datetime, DateTime.t(), enforce: true)
  end

  @impl true
  def type_code, do: @type_code

  @impl true
  def datetime(%__MODULE__{datetime: datetime}), do: datetime

  @impl true
  def pack(%__MODULE__{
        kind: kind,
        request_id: request_id,
        format: format,
        compression: compression,
        request_payload: request_payload,
        datetime: %DateTime{} = datetime
      })
      when kind in @kinds and is_integer(request_id) and request_id >= 0 and format in @data_formats and
             compression in @compression_types do
    compressed =
      request_payload
      |> validate_format!(kind)
      |> serialize!(format)
      |> compress!(compression)

    data_size = byte_size(compressed)

    <<
      @kind_codes[kind]::unsigned-integer-size(1)-unit(8),
      request_id::unsigned-integer-size(4)-unit(8),
      @data_format_codes[format]::unsigned-integer-size(1)-unit(8),
      @compression_type_codes[compression]::unsigned-integer-size(1)-unit(8),
      DateTime.to_unix(datetime)::unsigned-integer-size(4)-unit(8),
      data_size::unsigned-integer-size(3)-unit(8),
      compressed::binary-size(data_size)-unit(8)
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
        <<kind_code::unsigned-integer-size(1)-unit(8), request_id::unsigned-integer-size(4)-unit(8),
          format_code::unsigned-integer-size(1)-unit(8), compression_code::unsigned-integer-size(1)-unit(8),
          datetime::unsigned-integer-size(4)-unit(8), data_size::unsigned-integer-size(3)-unit(8),
          data::binary-size(data_size)-unit(8)>>
      ) do
    compression = @compression_type_codes_reverse[compression_code]
    format = @data_format_codes_reverse[format_code]

    decoded_payload =
      data
      |> decompress(compression)
      |> deserialize(format)

    {:ok,
     %__MODULE__{
       kind: @kind_codes_reverse[kind_code],
       format: format,
       compression: compression,
       request_id: request_id,
       request_payload: decoded_payload,
       datetime: DateTime.from_unix!(datetime)
     }}
  rescue
    error ->
      {:error,
       %ParseError{
         message: "Error parsing configuration data",
         reason: {error, __STACKTRACE__},
         data: %{payload: data}
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

  defp compress!(data, :none), do: data

  defp compress!(data, :brotli) do
    case :brotli.encode(data) do
      {:ok, compressed} ->
        compressed

      :error ->
        raise "Failed to compress data with brotli"
    end
  end

  defp decompress(data, :none), do: data

  defp decompress(data, :brotli) do
    case :brotli.decode(data) do
      {:ok, decompressed} ->
        decompressed

      :error ->
        raise "Failed to decompress data with brotli"
    end
  end

  defp serialize!(data, :json), do: Jason.encode!(data)
  defp serialize!(data, :msgpack), do: Msgpax.pack!(data, iodata: false)

  defp deserialize(data, :json), do: Jason.decode!(data)
  defp deserialize(data, :msgpack), do: Msgpax.unpack!(data)

  def validate_format!(nil, :request_schema), do: nil
  def validate_format!(nil, :request_full_config), do: nil

  def validate_format!(data, :set_config) do
    JSV.validate!(data, @json_patch_schema)
  end

  def validate_format!(data, kind) when is_map(data) and kind in [:full_report, :partial_report] do
    if not Map.has_key?(data, "version") or not Map.has_key?(data, "revision") do
      raise ArgumentError, "data must have version and revision fields"
    end

    data
  end

  def validate_format!(paths, :request_partial_config) when is_list(paths) do
    if Enum.all?(paths, &(is_binary(&1) and String.match?(&1, ~r/^#?(|(\/([^\/~]|~[01])*)*)$/))) do
      paths
    else
      raise ArgumentError, "request_partial_config paths must be JSON Pointer strings"
    end
  end

  # :schema — precisa ser um JSON Schema sintaticamente válido, e declarar
  # version/revision como exige o CONTRACT.md
  def validate_format!(schema, :schema) when is_map(schema) do
    JSV.build!(schema)

    required = schema["required"] || []
    properties = schema["properties"] || %{}

    cond do
      "version" not in required or "revision" not in required ->
        raise ArgumentError, ~s(schema must require both "version" and "revision")

      not match?(%{"const" => _}, properties["version"]) ->
        raise ArgumentError, "properties.version must be a const"

      not match?(%{"type" => "integer"}, properties["revision"]) ->
        raise ArgumentError, "properties.revision must be an integer"

      true ->
        schema
    end
  end

  def validate_format!(_data, kind) do
    raise ArgumentError, "invalid data format for #{inspect(kind)}"
  end
end
