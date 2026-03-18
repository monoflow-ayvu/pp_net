defmodule PPNet.PackError do
  @moduledoc """
  Error struct for parsing errors
  """

  @derive Jason.Encoder

  defstruct [:message, :reason, :data]

  @type t :: %__MODULE__{
          message: String.t(),
          reason: any()
        }
end
