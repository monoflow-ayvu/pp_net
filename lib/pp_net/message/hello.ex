defmodule PPNet.Message.Hello do
  @moduledoc """
  This module defines the `PPNet.Message.Hello` struct and provides functions to parse
  a binary or list representation of a Hello message into this struct.
  """
  @behaviour PPNet.Message

  use TypedStruct

  import Bitwise, only: [band: 2, bor: 2]

  alias PPNet.Message.Hello
  alias PPNet.PackError
  alias PPNet.ParseError

  @derive Jason.Encoder
  @type_code 1

  @capability_bits [brotli: 0x01, gzip: 0x02, heatshrink: 0x04]
  @capability_masks Map.new(@capability_bits)

  defguard is_valid_types(unique_id, board_identifier, version, board_version, boot_id)
           when is_binary(unique_id) and is_binary(board_identifier) and
                  is_integer(version) and version >= 0 and
                  is_integer(board_version) and board_version >= 0 and
                  is_integer(boot_id) and boot_id >= 0

  defguard is_valid_types_to_parse(
             unique_id,
             board_identifier,
             version,
             board_version,
             boot_id,
             datetime_unix
           )
           when is_binary(unique_id) and is_binary(board_identifier) and
                  is_integer(version) and version >= 0 and
                  is_integer(board_version) and board_version >= 0 and
                  is_integer(boot_id) and boot_id >= 0 and
                  is_integer(datetime_unix) and datetime_unix > 0

  # the old format (no datetime) only ever carried an integer ppnet_version
  defguardp is_legacy_ppnet_version(ppnet_version) when is_integer(ppnet_version) and ppnet_version >= 0

  # an integer on the wire up to v0.1.6, the library version string (e.g. "0.2.0") afterwards
  defguardp is_valid_ppnet_version(ppnet_version)
            when is_legacy_ppnet_version(ppnet_version) or is_binary(ppnet_version)

  typedstruct do
    @typedoc """
    The `PPNet.Message.Hello` struct

    ## Fields

    * `unique_id` - The unique ID of the device
    * `board_identifier` - The name of the board
    * `version` - The version of the software
    * `board_version` - The version of the board
    * `boot_id` - The boot ID of the board
    * `ppnet_version` - The version of the PPNet library
    * `datetime` - The timestamp when the hello message was sent
    * `capabilities` - List of supported compression algorithms: `:brotli`, `:gzip`, and
      `:heatshrink`. The wire format encodes this list as a bitfield; unassigned bits are ignored.
    * `extra` - Optional arbitrary key/value data, such as cellular identifiers
    """

    field(:unique_id, String.t(), enforce: true)
    field(:board_identifier, String.t(), enforce: true)
    field(:version, non_neg_integer(), enforce: true)
    field(:board_version, non_neg_integer(), enforce: true)
    field(:boot_id, non_neg_integer(), enforce: true)
    field(:ppnet_version, String.t())
    field(:datetime, DateTime.t(), enforce: true)
    field(:capabilities, list(:brotli | :gzip | :heatshrink), default: [])
    field(:extra, %{optional(String.t()) => any()}, default: %{})
  end

  @impl true
  def type_code, do: @type_code

  @impl true
  def datetime(%__MODULE__{datetime: datetime}), do: datetime

  @impl true
  def pack(message)

  def pack(%__MODULE__{
        unique_id: unique_id,
        board_identifier: board_identifier,
        version: version,
        board_version: board_version,
        boot_id: boot_id,
        datetime: %DateTime{} = datetime,
        capabilities: capabilities,
        extra: extra
      })
      when is_valid_types(unique_id, board_identifier, version, board_version, boot_id) and is_list(capabilities) and
             is_map(extra) do
    case capabilities_to_bitfield(capabilities) do
      {:ok, capability_bitfield} ->
        fields = [
          unique_id,
          board_identifier,
          version,
          board_version,
          boot_id,
          ppnet_version(),
          DateTime.to_unix(datetime)
        ]

        fields =
          cond do
            map_size(extra) > 0 -> fields ++ [capability_bitfield, extra]
            capability_bitfield != 0 -> fields ++ [capability_bitfield]
            true -> fields
          end

        {:ok, Msgpax.pack!(fields, iodata: false)}

      :error ->
        {:error, %PackError{message: "Invalid struct provided to pack/1", reason: :invalid_struct}}
    end
  rescue
    error ->
      {:error, %PackError{message: "Invalid struct provided to pack/1", reason: {error, __STACKTRACE__}}}
  end

  def pack(_message) do
    {:error, %PackError{message: "Invalid struct provided to pack/1", reason: :invalid_struct}}
  end

  @impl true
  def parse(payload)

  def parse(packaged_body) when is_binary(packaged_body) do
    with {:ok, unpacked_body} <- Msgpax.unpack(packaged_body) do
      parse(unpacked_body)
    end
  end

  # Maintains compatibility with the old format (without datetime)
  # Since it doesn't have a datetime, it sets `now` as the default value.
  def parse([unique_id, board_identifier, version, board_version, boot_id, ppnet_version])
      when is_valid_types(unique_id, board_identifier, version, board_version, boot_id) and
             is_legacy_ppnet_version(ppnet_version) do
    {:ok,
     %Hello{
       unique_id: to_string(unique_id),
       board_identifier: to_string(board_identifier),
       version: version,
       board_version: board_version,
       boot_id: boot_id,
       ppnet_version: ppnet_version,
       capabilities: [],
       datetime: nil
     }}
  end

  def parse([unique_id, board_identifier, version, board_version, boot_id, ppnet_version, datetime])
      when is_valid_types_to_parse(unique_id, board_identifier, version, board_version, boot_id, datetime) and
             is_valid_ppnet_version(ppnet_version) do
    {:ok,
     %Hello{
       unique_id: to_string(unique_id),
       board_identifier: to_string(board_identifier),
       version: version,
       board_version: board_version,
       boot_id: boot_id,
       ppnet_version: ppnet_version,
       capabilities: [],
       datetime: DateTime.from_unix!(datetime)
     }}
  end

  def parse([
        unique_id,
        board_identifier,
        version,
        board_version,
        boot_id,
        ppnet_version,
        datetime,
        capability_bitfield
      ])
      when is_valid_types_to_parse(unique_id, board_identifier, version, board_version, boot_id, datetime) and
             is_valid_ppnet_version(ppnet_version) and is_integer(capability_bitfield) and capability_bitfield >= 0 do
    {:ok,
     %Hello{
       unique_id: to_string(unique_id),
       board_identifier: to_string(board_identifier),
       version: version,
       board_version: board_version,
       boot_id: boot_id,
       ppnet_version: ppnet_version,
       capabilities: capabilities_from_bitfield(capability_bitfield),
       datetime: DateTime.from_unix!(datetime)
     }}
  end

  def parse([
        unique_id,
        board_identifier,
        version,
        board_version,
        boot_id,
        ppnet_version,
        datetime,
        capability_bitfield,
        extra
      ])
      when is_map(extra) do
    with {:ok, hello} <-
           parse([
             unique_id,
             board_identifier,
             version,
             board_version,
             boot_id,
             ppnet_version,
             datetime,
             capability_bitfield
           ]) do
      {:ok, %{hello | extra: extra}}
    end
  end

  def parse(unpacked_body) when is_list(unpacked_body) do
    {:error,
     %ParseError{
       message: "The message body does not match the expected format",
       reason: :unknown_format,
       data: {:unpacked_body, unpacked_body}
     }}
  end

  defp capabilities_to_bitfield(capabilities), do: capabilities_to_bitfield(capabilities, 0)

  defp capabilities_to_bitfield([], bitfield), do: {:ok, bitfield}

  defp capabilities_to_bitfield([capability | rest], bitfield) do
    case Map.fetch(@capability_masks, capability) do
      {:ok, mask} -> capabilities_to_bitfield(rest, bor(bitfield, mask))
      :error -> :error
    end
  end

  defp capabilities_to_bitfield(_invalid, _bitfield), do: :error

  defp capabilities_from_bitfield(bitfield) do
    for {capability, mask} <- @capability_bits, band(bitfield, mask) != 0, do: capability
  end

  defp ppnet_version, do: to_string(Application.spec(:pp_net, :vsn))
end
