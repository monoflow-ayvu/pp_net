defmodule PPNet.MixProject do
  use Mix.Project

  @source_url "https://github.com/monoflow-ayvu/pp_net"
  @version "VERSION"
           |> File.read!()
           |> String.trim()

  def project do
    [
      app: :pp_net,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      compilers: [:elixir_make] ++ Mix.compilers(),
      make_clean: ["clean"],
      make_error_message: "Heatshrink requires make and a C compiler to build its native binding",
      make_precompiler: {:nif, CCPrecompiler},
      make_precompiler_filename: "pp_net_heatshrink",
      make_precompiler_priv_paths: ["pp_net_heatshrink.so", "pp_net_heatshrink.dll"],
      make_precompiler_url: "#{@source_url}/releases/download/v#{@version}/@{artefact_filename}",
      make_precompiler_nif_versions: [versions: ["2.17"]],
      make_force_build: System.get_env("PP_NET_FORCE_BUILD") == "1",
      cc_precompiler: [
        cleanup: "clean",
        only_listed_targets: false,
        compilers: %{
          {:unix, :linux} => %{
            "x86_64-linux-gnu" => "x86_64-linux-gnu-",
            "aarch64-linux-gnu" => "aarch64-linux-gnu-"
          },
          {:unix, :darwin} => %{
            "x86_64-apple-darwin" => {"cc", "c++", "<%= cc %> -arch x86_64", "<%= cxx %> -arch x86_64"},
            "aarch64-apple-darwin" => {"cc", "c++", "<%= cc %> -arch arm64", "<%= cxx %> -arch arm64"}
          },
          {:win32, :nt} => %{
            "x86_64-windows-msvc" => {"cl", "cl"}
          }
        }
      ],
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      package: package(),
      test_coverage: [tool: ExCoveralls],
      dialyzer: [ignore_warnings: "dialyzer_ignore_warnings.exs"],
      organization: "monoflow",
      docs: docs()
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
      {:reed_solomon_ex, "~> 0.2.0"},
      {:elixir_uuid, "~> 1.2"},
      {:brotli, "~> 0.3.3"},
      {:elixir_make, "~> 0.9.0", runtime: false},
      {:cc_precompiler, "~> 0.1.11", runtime: false},
      {:jsv, "~> 0.28.0"},
      {:nimble_options, "~> 1.1"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:quokka, "~> 2.11", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18.3", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

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
      licenses: ["MIT", "ISC"],
      links: %{"GitHub" => @source_url},
      maintainers: ["JVMartyns", "Fernando Mumbach"],
      description: "Message protocol with error correction (Reed-Solomon) and framing (COBS)",
      files: ~w(lib c_src Makefile Makefile.win checksum.exs mix.exs README.md CHANGELOG.md LICENSE VERSION)
    }
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.cobertura": :test
      ]
    ]
  end

  def docs do
    [
      name: "PPNet",
      source_ref: "v#{@version}",
      source_url: @source_url,
      main: "PPNet",
      extras: [{"README.md", [title: "README"]}, "CHANGELOG.md", "LICENSE"]
    ]
  end
end
