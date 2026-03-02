defmodule PPNet.Message do
  @moduledoc """
  This module defines the `PPNet.Message` protocol, which provides functions to pack
  and parse messages.

  ## Transport fields (standard in all parsed messages)

  All message structs must have, at the end, two optional fields filled
  by the transport layer (PPNet) after decoding:

  * `:checksum` – `non_neg_integer()` – Adler32 checksum of the payload
  * `:valid` – `boolean()` – whether the checksum matches

  This way, the consumer can directly pattern match on any message, for example:
  `%Hello{valid: true}` or `%Ping{valid: false}`.
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
