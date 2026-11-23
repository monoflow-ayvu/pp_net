defmodule PPNet.Heatshrink do
  @moduledoc false

  @on_load :load_nif

  @spec encode(binary()) :: {:ok, binary()} | :error
  def encode(_data), do: :erlang.nif_error(:nif_not_loaded)

  @spec decode(binary()) :: {:ok, binary()} | :error
  def decode(_data), do: :erlang.nif_error(:nif_not_loaded)

  def load_nif do
    :pp_net
    |> Application.app_dir("priv/pp_net_heatshrink")
    |> String.to_charlist()
    |> :erlang.load_nif(0)
  end
end
