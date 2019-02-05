use Mix.Config

# Basically this config will be used on realease building.
# And application will use this config for Docker build

config :chain, base_path: "/opt/chains"
config :chain, snapshot_base_path: "/opt/snapshots"
config :chain, geth_password_file: "/opt/built/priv/presets/geth/account_password"
config :chain, ganache_executable: "ganache-cli"
config :chain, ganache_wrapper_file: "/opt/built/priv/presets/ganache/wrapper.sh"

config :chain, backend_proxy_node: :"testchain_backendgateway@testchain-backendgateway.local"

config :chain, front_url: System.get_env("FRONT_URL") || "ex-testchain.local"

# Place where all dets DBs will be
config :storage, dets_db_path: "/opt/chains"
