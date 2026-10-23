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

  @doc """
  The error returned by `pack/1` when `hop` is not an integer between 0 and 255
  """
  @spec invalid_hop() :: {:error, t()}
  def invalid_hop do
    {:error, %__MODULE__{message: "hop must be an integer between 0 and 255", reason: :invalid_hop}}
  end
end
