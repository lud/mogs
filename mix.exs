defmodule Mogs.MixProject do
  use Mix.Project

  def project do
    [
      app: :mogs,
      version: "0.1.0",
      elixir: "~> 1.10",
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
      # Utils
      {:decompilerl, github: "niahoo/decompilerl", only: [:dev]},
      {:credo, "~> 1.1", only: [:dev, :test], runtime: false}
    ]
  end
end
