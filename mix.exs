defmodule Paddle.Mixfile do
  use Mix.Project

  def project do
    [
      app: :paddle,
      version: "0.1.4",
      description: "A library simplifying LDAP usage",
      elixir: "~> 1.3",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      source_url: "https://github.com/minijackson/paddle",
      homepage_url: "https://github.com/minijackson/paddle",
      elixirc_paths: elixirc_paths(Mix.env()),
      docs: [extras: ["README.md"]]
    ]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [applications: [:logger, :eldap, :ssl], mod: {Paddle.Application, []}]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:ex_doc, "~> 0.19", only: :dev, runtime: false},
      {:dialyxir, "~> 0.5", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.2", only: [:dev, :test], runtime: false},
      {:inch_ex, "~> 0.5", only: [:dev, :test], runtime: false}
    ]
  end

  defp package() do
    [
      name: :paddle,
      maintainers: ["Rémi Nicole"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/minijackson/paddle"}
    ]
  end

  defp elixirc_paths(:prod), do: ["lib"]
  defp elixirc_paths(:dev), do: elixirc_paths(:prod)
  defp elixirc_paths(:test), do: ["test/support"] ++ elixirc_paths(:dev)
end
