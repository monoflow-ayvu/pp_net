defmodule PPNet.Message.ConfigAck do
  @moduledoc """
  Application-level ACK for a `PPNet.Message.ConfigData` message, keyed by `request_id`.

  Whoever sends a `ConfigData` generates its `request_id`; whoever receives it responds
  with a `ConfigAck` echoing that same `request_id`, so the sender can correlate this
  response with the message it sent. `status: :ok` confirms the payload was processed
  successfully (e.g. a patch was applied); any other status explains why it wasn't.

  This is distinct from `PPNet.Message.ChunkedMessageAck`, which only confirms that a
  chunked transfer's bytes arrived intact — a message can pass that and still fail here
  (e.g. a patch that reassembles fine but fails schema validation).
  """
  @behaviour PPNet.Message

  use TypedStruct

  alias PPNet.PackError
  alias PPNet.ParseError

  @type_code 10
  @status_code %{
    ok: 0,
    # failed validation against the schema
    invalid_patch: 1,
    # config version or revision didn't match
    conflict: 2,
    # data did not decode (malformed JSON/msgpack)
    decode_error: 3,
    unknown: 4
  }
  @statuses Map.keys(@status_code)

  @status_code_reserve Map.new(@status_code, fn {k, v} -> {v, k} end)

  @derive Jason.Encoder
  typedstruct do
    field(:request_id, non_neg_integer(), enforce: true)
    field(:status, atom(), enforce: true)
    field(:datetime, DateTime.t(), enforce: true)
  end

  @impl true
  def type_code, do: @type_code

  @impl true
  def datetime(%__MODULE__{datetime: datetime}), do: datetime

  @impl true
  def pack(%__MODULE__{request_id: request_id, status: status, datetime: %DateTime{} = datetime})
      when is_integer(request_id) and request_id >= 0 and status in @statuses do
    <<
      request_id::unsigned-integer-size(4)-unit(8),
      @status_code[status]::unsigned-integer-size(1)-unit(8),
      DateTime.to_unix(datetime)::unsigned-integer-size(4)-unit(8)
    >>
  rescue
    error ->
      {:error, %PackError{message: "Invalid struct provided to pack/1", reason: {error, __STACKTRACE__}}}
  end

  def pack(_message) do
    {:error, %PackError{message: "Invalid struct provided to pack/1", reason: :invalid_struct}}
  end

  @impl true
  def parse(
        <<request_id::unsigned-integer-size(4)-unit(8), status_code::unsigned-integer-size(1)-unit(8),
          datetime::unsigned-integer-size(4)-unit(8)>>
      ) do
    {:ok,
     %__MODULE__{
       request_id: request_id,
       status: @status_code_reserve[status_code],
       datetime: DateTime.from_unix!(datetime)
     }}
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
