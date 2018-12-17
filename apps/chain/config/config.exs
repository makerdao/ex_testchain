# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

# This configuration is loaded before any dependency and is restricted
# to this project. If another project depends on this project, this
# file won't be loaded nor affect the parent project. For this reason,
# if you want to provide default values for your application for
# 3rd-party users, it should be done in your "mix.exs" file.

config :porcelain, driver: Porcelain.Driver.Basic

# Amount of time in ms process allowed to perform "blocking" work before supervisor will terminate it
config :chain, kill_timeout: 180_000

# Default folder where all chain db's will be created, please use full path
# Note that chain id will be added as final folder.
# Example: with `config :chain, base_path: "/tmp/chains"`
# Final chain path will be 
# `/tmp/chains/some-id-here`
config :chain, base_path: "/tmp/chains"

# Default path where snapshots will be stored for chain
# chain id will be added as a target folder under this path
config :chain, snapshot_base_path: "/tmp/snapshots"

# Default location of account password file. 
# For dev env it will be in related to project root. In Docker it will be replaced with 
# file from `rel/config/config.exs`
config :chain, geth_password_file: Path.absname("priv/presets/geth/account_password")

config :chain, ganache_executable: Path.absname("priv/presets/ganache-cli/cli.js")
config :chain, ganache_wrapper_file: Path.absname("priv/presets/ganache/wrapper.sh")

# config :logger, level: :info
