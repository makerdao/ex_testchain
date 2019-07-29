import Config

config :chain, base_path: "/opt/chains"
config :chain, snapshot_base_path: "/opt/snapshots"
config :chain, geth_executable: "geth"
config :chain, geth_password_file: "/opt/built/priv/presets/geth/account_password"
config :chain, ganache_executable: "ganache-cli"
config :chain, ganache_wrapper_file: "/opt/built/priv/presets/ganache/wrapper.sh"
config :chain, geth_vdb_executable: "geth_vdb"

config :chain, backend_proxy_node: :"staxx@staxx.local"

config :chain, front_url: System.fetch_env!("FRONT_URL")

# Place where all dets DBs will be
config :storage, dets_db_path: "/opt/chains"
