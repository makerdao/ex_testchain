defmodule Cli.MixProject do
  use Mix.Project

  def project do
    [
      app: :cli,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.7",
      escript: escript(),
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

  defp escript do
    [
      main_module: Cli.Main,
      name: "ex_testchain",
      path: "../../bin/ex_testchain"
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:chain, in_umbrella: true},
      {:cli_spinners, "~> 0.1.0"}
    ]
  end
end
