defmodule Mogs.MixProject do
  use Mix.Project

  @description """
  Mutiplayer Online Game Server library
  """

  def project do
    [
      app: :mogs,
      version: "0.2.0",
      description: @description,
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      consolidate_protocols: Mix.env() != :test,
      package: package()
    ]
  end

  defp package() do
    [
      name: "mogs",
      licenses: ["MIT"],
      links: []
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Mogs.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Deps
      {:time_queue, ">= 0.5.0"},
      {:nimble_options, "~> 0.3.0"},

      # Test Deps
      {:cubdb, "~> 1.0.0-rc3", only: [:test]},

      # Utils
      {:inch_ex, "~> 2.0", only: [:dev]},
      {:dialyxir, ">= 0.0.0", only: [:dev], runtime: false},
      {:decompilerl, github: "niahoo/decompilerl", only: [:dev]},
      {:ex_doc, ">= 0.0.0", only: [:dev], runtime: false},
      {:credo, "~> 1.1", only: [:dev], runtime: false},
      {:todo, "~> 1.4.1"}
    ]
  end
end
