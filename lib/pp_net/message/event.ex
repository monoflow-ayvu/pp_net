defmodule PPNet.Message.Event do
  @moduledoc """
  This module defines the `PPNet.Message.Event` struct and provides functions to parse
  a binary or list representation of an Event message into this struct.
  """
  @behaviour PPNet.Message

  use TypedStruct

  alias PPNet.PackError
  alias PPNet.ParseError

  @derive Jason.Encoder
  @type_code 4
  @type event_kind :: :detection
  @event_kind_to_code %{detection: 1}
  @code_to_event_kind Map.new(@event_kind_to_code, fn {k, v} -> {v, k} end)
  @valid_event_kind_codes Map.values(@event_kind_to_code)
  @valid_event_kinds Map.keys(@event_kind_to_code)

  typedstruct do
    @typedoc """
    The `PPNet.Message.Event` struct

    ## Fields

    * `kind` - The kind of event (`:detection`)
    * `data` - Arbitrary key/value payload associated with the event
    * `datetime` - Timestamp of the event
    """

    field(:kind, event_kind(), enforce: true)
    field(:data, %{optional(String.t()) => any()}, enforce: true)
    field(:datetime, DateTime.t(), enforce: true)
  end

  @impl true
  def type_code, do: @type_code

  @impl true
  def datetime(%__MODULE__{datetime: datetime}), do: datetime

  @impl true
  def pack(%__MODULE__{kind: kind, data: data, datetime: %DateTime{} = datetime})
      when kind in @valid_event_kinds and is_map(data) do
    Msgpax.pack!(
      [@event_kind_to_code[kind], data, DateTime.to_unix(datetime)],
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

  def parse([kind_code, data, datetime])
      when kind_code in @valid_event_kind_codes and is_map(data) and is_integer(datetime) do
    {:ok, %__MODULE__{kind: @code_to_event_kind[kind_code], data: data, datetime: DateTime.from_unix!(datetime)}}
  end

  def parse([kind_code, data]) when kind_code in @valid_event_kind_codes and is_map(data) do
    {:ok, %__MODULE__{kind: @code_to_event_kind[kind_code], data: data, datetime: nil}}
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
