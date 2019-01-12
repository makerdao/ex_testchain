use Mix.Config

config :chain, ganache_executable: System.get_env("GANACHE_EXECUTABLE") || Path.expand("#{__DIR__}/../../../priv/presets/ganache-cli/cli.js")