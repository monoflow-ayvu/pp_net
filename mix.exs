defmodule PpNet.MixProject do
  use Mix.Project

  @source_url "https://github.com/monoflow-ayvu/pp_net"

  def project do
    [
      app: :pp_net,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      package: package(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.cobertura": :test,
      ]
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
      {:quokka, "~> 2.11", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18.3", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      check: [
        "format --check-formatted",
        "deps.unlock --check-unused",
        "credo suggest --strict --all"
      ]
    ]
  end

  defp package do
    %{
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      maintainers: ["JVMartyns", "Fernando Mumbach"],
      description: "A wrapper that simplifies interactions with the official Cloud Firestore API"
    }
  end
end
