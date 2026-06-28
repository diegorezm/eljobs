defmodule Eljobs.MixProject do
  use Mix.Project

  def project do
    [
      app: :eljobs,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Eljobs, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:uuid, "~> 1.1"},
      {:bandit, "~> 1.12"},
      {:plug, "~> 1.20"},
      {:jason, "~> 1.4"}
    ]
  end
end
