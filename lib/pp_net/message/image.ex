defmodule PPNet.Message.Image do
  @behaviour PPNet.Message

  use TypedStruct

  alias PPNet.ParseError

  @type_code 5

  typedstruct do
    field(:data, binary(), enforce: true)
    field(:checksum, non_neg_integer())
    field(:valid, boolean())
  end

  @impl true
  def type_code, do: @type_code

  @impl true
  def pack(%__MODULE__{} = message) do
    message.data
  end

  @impl true
  def parse(data) when is_binary(data) do
    {:ok, %__MODULE__{data: data}}
  end

  def parse(data) do
    {:error,
     %ParseError{
       message: "The message body does not match the expected format",
       reason: :unknown_format,
       data: %{payload: data}
     }}
  end
end
