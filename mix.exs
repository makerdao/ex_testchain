defmodule TestChain.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      start_permanent: Mix.env() == :prod,
      version: "0.1.0",
      deps: deps(),
      releases: releases()
    ]
  end

  defp releases() do
    [
      ex_testchain: [
        include_executables_for: [:unix],
        applications: [
          chain: :permanent,
          json_rpc: :permanent,
          storage: :permanent
        ]
      ]
    ]
  end

  # Dependencies listed here are available only for this
  # project and cannot be accessed from applications inside
  # the apps folder.
  #
  # Run "mix help deps" for examples and options.
  defp deps do
    [
      {:credo, "~> 1.0.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0.0-rc.4", only: [:dev], runtime: false}
    ]
  end
end
