use Mix.Config

config :chain, ganache_executable: System.get_env("GANACHE_EXECUTABLE") || Path.expand("#{__DIR__}/../../../priv/presets/ganache-cli/cli.js")

config :logger,
  backends: [:console],
  level: :warn,
  compile_time_purge_matching: [
    [level_lower_than: :warn]
  ]