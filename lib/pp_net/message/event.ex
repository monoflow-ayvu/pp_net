defmodule PPNet.Message.Event do
  @moduledoc """
  This module defines the `PPNet.Message.Event` struct and provides functions to parse
  a binary or list representation of an Event message into this struct.
  """
  @behaviour PPNet.Message

  use TypedStruct

  alias PPNet.ParseError

  @type_code 4

  typedstruct do
    field(:kind, String.t(), enforce: true)
    field(:data, %{optional(String.t()) => any()}, enforce: true)
    field(:checksum, non_neg_integer())
    field(:valid, boolean())
  end

  @impl true
  def type_code, do: @type_code

  @impl true
  def pack(%__MODULE__{} = event) do
    Msgpax.pack!(
      [event.kind, event.data],
      iodata: false
    )
  end

  @impl true
  def parse(packaged_body) when is_binary(packaged_body) do
    with {:ok, unpacked_body} <- Msgpax.unpack(packaged_body) do
      parse(unpacked_body)
    end
  end

  def parse([kind, data]) when is_binary(kind) and is_map(data) do
    {:ok, %__MODULE__{kind: kind, data: data}}
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
