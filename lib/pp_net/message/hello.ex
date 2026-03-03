defmodule PPNet.Message.Hello do
  @moduledoc """
  This module defines the `PPNet.Message.Hello` struct and provides functions to parse
  a binary or list representation of a Hello message into this struct.
  """
  @behaviour PPNet.Message

  use TypedStruct

  alias PPNet.Message.Hello
  alias PPNet.ParseError

  @derive Jason.Encoder
  @type_code 1

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
    """

    field(:unique_id, String.t(), enforce: true)
    field(:board_identifier, String.t(), enforce: true)
    field(:version, non_neg_integer(), enforce: true)
    field(:board_version, non_neg_integer(), enforce: true)
    field(:boot_id, non_neg_integer(), enforce: true)
    field(:ppnet_version, non_neg_integer(), default: 1)
  end

  @impl true
  def type_code, do: @type_code

  @impl true
  def pack(%__MODULE__{} = message) do
    Msgpax.pack!(
      [
        message.unique_id,
        message.board_identifier,
        message.version,
        message.board_version,
        message.boot_id,
        message.ppnet_version
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

  # credo:disable-for-lines:2
  def parse([unique_id, board_identifier, version, board_version, boot_id, ppnet_version])
      when is_binary(unique_id) and is_binary(board_identifier) and is_integer(version) and is_integer(board_version) and
             is_integer(boot_id) and is_integer(ppnet_version) do
    {:ok,
     %Hello{
       unique_id: to_string(unique_id),
       board_identifier: to_string(board_identifier),
       version: version,
       board_version: board_version,
       boot_id: boot_id,
       ppnet_version: ppnet_version
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
