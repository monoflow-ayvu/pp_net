defmodule PPNet.Message do
  @moduledoc """
  This module defines the `PPNet.Message` protocol, which provides functions to pack
  and parse messages.
  """
  alias PPNet.ParseError

  @callback pack(message :: struct()) :: binary()
  @callback parse(data :: binary()) :: {:ok, struct()} | {:error, %ParseError{}}
  @callback type_code() :: non_neg_integer()
end
