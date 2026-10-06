defmodule PPNet.Message do
  @moduledoc """
  This module defines the `PPNet.Message` protocol, which provides functions to pack
  and parse messages.
  """
  alias PPNet.ParseError

  @optional_callbacks pack: 2

  @callback pack(message :: struct()) :: binary()
  @callback pack(message :: struct(), limit :: pos_integer()) :: binary()
  @callback parse(data :: binary()) :: {:ok, struct()} | {:error, %ParseError{}}
  @callback datetime(message :: struct()) :: DateTime.t()
  @callback type_code() :: non_neg_integer()
end
