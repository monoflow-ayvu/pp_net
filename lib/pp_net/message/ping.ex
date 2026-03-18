defmodule PPNet.Message.Ping do
  @moduledoc """
  This module defines the `PPNet.Message.Ping` struct and provides functions to parse
  a binary or list representation of a Ping message into this struct.
  """
  @behaviour PPNet.Message

  use TypedStruct

  alias PPNet.Message.Ping
  alias PPNet.PackError
  alias PPNet.ParseError

  @derive Jason.Encoder
  @type_code 3

  typedstruct do
    @typedoc """
    The `PPNet.Message.Ping` struct

    ## Fields

    * `session_id` - Session ID
    * `temperature` - CPU/board temperature in Celsius
    * `uptime_ms` - Device uptime in milliseconds
    * `location` - GPS location in WGS 84 (EPSG:4326): `lat` and `lon` in decimal degrees, `accuracy` in meters
    * `cpu` - CPU usage as a float between 0.0 and 1.0
    * `tpu_memory_percent` - TPU memory usage percentage (0-100)
    * `tpu_ping_ms` - TPU round-trip ping time in milliseconds
    * `wifi` - List of visible WiFi networks, each with `mac` (string) and `rssi` (integer, dBm)
    * `storage` - Disk usage in kilobytes (KB): `total` and `used`
    * `extra` - Optional arbitrary key/value data
    """
    field(:session_id, String.t(), enforce: true)
    field(:temperature, float(), enforce: true)
    field(:uptime_ms, integer(), enforce: true)

    field(:location, %{required(:lat) => float(), required(:lon) => float(), required(:accuracy) => integer()},
      enforce: true
    )

    field(:cpu, float(), enforce: true)
    field(:tpu_memory_percent, integer(), enforce: true)
    field(:tpu_ping_ms, integer(), enforce: true)
    field(:wifi, list(%{required(:mac) => String.t(), required(:rssi) => integer()}), default: [])
    field(:storage, %{required(:total) => integer(), required(:used) => integer()}, enforce: true)
    field(:extra, %{optional(String.t()) => any()}, default: %{})
  end

  @impl true
  def type_code, do: @type_code

  defguardp is_valid_location(lat, lon, accuracy)
            when is_float(lat) and is_float(lon) and is_integer(accuracy)

  defguardp is_valid_cpu(cpu) when is_float(cpu) and cpu >= 0.0 and cpu <= 1.0

  defguardp is_valid_tpu_memory(tpu_memory_percent)
            when is_integer(tpu_memory_percent) and tpu_memory_percent >= 0 and
                   tpu_memory_percent <= 100

  defguard valid_wifi_lingh(wifi) when is_list(wifi) and length(wifi) <= 10

  defguardp is_valid_storage(total, used) when is_integer(total) and is_integer(used)

  @impl true
  # credo:disable-for-lines:14
  def pack(%__MODULE__{
        session_id: session_id,
        temperature: temperature,
        uptime_ms: uptime_ms,
        location: %{lat: lat, lon: lon, accuracy: accuracy} = location,
        cpu: cpu,
        tpu_memory_percent: tpu_memory_percent,
        tpu_ping_ms: tpu_ping_ms,
        wifi: wifi,
        storage: %{total: total, used: used} = storage,
        extra: extra
      })
      when is_float(temperature) and is_integer(uptime_ms) and is_valid_location(lat, lon, accuracy) and
             is_valid_cpu(cpu) and is_valid_tpu_memory(tpu_memory_percent) and is_integer(tpu_ping_ms) and is_list(wifi) and
             is_valid_storage(total, used) and is_map(extra) and valid_wifi_lingh(wifi) do
    Msgpax.pack!(
      [
        pack_session_id(session_id),
        temperature,
        uptime_ms,
        pack_location(location),
        cpu,
        tpu_memory_percent,
        tpu_ping_ms,
        pack_wifi(wifi),
        pack_storage(storage),
        extra
      ],
      iodata: false
    )
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

  def parse([session_id, temperature, uptime_ms, location, cpu, tpu_memory_percent, tpu_ping_ms, wifi, storage, extra])
      when is_list(session_id) and is_float(temperature) and is_integer(uptime_ms) and is_list(location) and
             is_float(cpu) and is_integer(tpu_memory_percent) and is_integer(tpu_ping_ms) and is_list(wifi) and
             is_list(storage) and is_map(extra) do
    {:ok,
     %Ping{
       session_id: parse_session_id(session_id),
       temperature: temperature,
       uptime_ms: uptime_ms,
       location: parse_location(location),
       cpu: cpu,
       tpu_memory_percent: tpu_memory_percent,
       tpu_ping_ms: tpu_ping_ms,
       wifi: parse_wifi(wifi),
       storage: parse_storage(storage),
       extra: extra
     }}
  end

  def parse([temperature, uptime_ms, location, cpu, tpu_memory_percent, tpu_ping_ms, wifi, storage, extra])
      when is_float(temperature) and is_integer(uptime_ms) and is_list(location) and is_float(cpu) and
             is_integer(tpu_memory_percent) and is_integer(tpu_ping_ms) and is_list(wifi) and is_list(storage) and
             is_map(extra) do
    {:ok,
     %Ping{
       session_id: nil,
       temperature: temperature,
       uptime_ms: uptime_ms,
       location: parse_location(location),
       cpu: cpu,
       tpu_memory_percent: tpu_memory_percent,
       tpu_ping_ms: tpu_ping_ms,
       wifi: parse_wifi(wifi),
       storage: parse_storage(storage),
       extra: extra
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

  defp parse_location([lat, lon, accuracy]) when is_float(lat) and is_float(lon) and is_integer(accuracy) do
    %{lat: lat, lon: lon, accuracy: accuracy}
  end

  defp parse_wifi(wifi) when is_list(wifi), do: Enum.map(wifi, &parse_wifi_item/1)

  defp parse_wifi_item(<<mac::binary-size(6), rssi::signed-integer-size(1)-unit(8)>>) do
    mac_str =
      mac
      |> :binary.bin_to_list()
      |> Enum.map_join(":", &String.pad_leading(Integer.to_string(&1, 16), 2, "0"))

    %{mac: mac_str, rssi: rssi}
  end

  defp parse_storage([total, used]) when is_integer(total) and is_integer(used) do
    %{total: total, used: used}
  end

  defp pack_wifi(wifi) when is_list(wifi), do: Enum.map(wifi, &pack_wifi_item/1)

  defp pack_wifi_item(%{mac: mac, rssi: rssi}) do
    mac_binary =
      mac
      |> String.split(":")
      |> Enum.map(&String.to_integer(&1, 16))
      |> :binary.list_to_bin()

    <<mac_binary::binary-size(6), rssi::signed-integer-size(1)-unit(8)>>
  end

  defp pack_location(%{lat: lat, lon: lon, accuracy: accuracy}) do
    [lat, lon, accuracy]
  end

  defp pack_storage(%{total: total, used: used}) do
    [total, used]
  end

  defp pack_session_id(session_id) do
    session_id
    |> UUID.string_to_binary!()
    |> :binary.bin_to_list()
  end

  defp parse_session_id(session_id) do
    session_id
    |> :binary.list_to_bin()
    |> UUID.binary_to_string!()
  end
end
