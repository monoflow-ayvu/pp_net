defmodule PPNet.Message do
  @moduledoc """
  This module defines the `PPNet.Message` protocol, which provides functions to pack
  and parse messages.
  """
  alias PPNet.Message.ChunckedMessageBody
  alias PPNet.Message.ChunckedMessageHeader
  alias PPNet.Message.Event
  alias PPNet.Message.Hello
  alias PPNet.Message.Image
  alias PPNet.Message.Ping
  alias PPNet.Message.SingleCounter
  alias PPNet.ParseError

  @type message_module :: Hello | SingleCounter | Ping | Event | Image | ChunckedMessageHeader | ChunckedMessageBody

  @callback pack(message :: message_module()) :: binary()
  @callback parse(data :: binary()) :: {:ok, message_module()} | {:error, %ParseError{}}
  @callback type_code() :: non_neg_integer()
end
