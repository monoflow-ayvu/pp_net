defmodule PpNet.MixProject do
  use Mix.Project

  def project do
    [
      app: :pp_net,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:typed_struct, "~> 0.3.0"},
      {:msgpax, "~> 2.4"},
      {:jason, "~> 1.4"},
      {:cobs, "~> 0.2.0"},
      {:reed_solomon_ex, "~> 0.1.1"},
      {:credo, "~> 1.7"},
      {:quokka, "~> 2.11", only: [:dev, :test], runtime: false}
    ]
  end
end
