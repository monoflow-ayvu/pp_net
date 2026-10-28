defmodule PPNet.Guards do
  @moduledoc """
  Guards shared by more than one `PPNet.Message` module.

  Import only the ones a module needs, e.g. `import PPNet.Guards, only: [is_hop: 1]`.
  """

  @doc """
  True for a `hop`: an unsigned 8-bit integer (0 to 255), the address of a device on the board's
  internal bus. `0` is the board itself.
  """
  defguard is_hop(hop) when is_integer(hop) and hop >= 0 and hop <= 255
end
