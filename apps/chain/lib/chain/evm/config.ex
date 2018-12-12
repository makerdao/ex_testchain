defmodule Chain.EVM.Config do
  @moduledoc """
  Default start configuration for new EVM.

  Options:
  - `type` - EVM type. (Default: `:ganache`)
  - `id` - Random unique internal process identificator. Example: `"11296068888839073704"`. If empty system will generate it automatically
  - `http_port` - HTTP JSONRPC port (Default: `8545`)
  - `ws_port` - WS JSONRPC port (for ganache it will be ignored and `http_port` will be used) (Default: `8546`)
  - `network_id` - Network ID (Default: `999`)
  - `db_path` - Specify a path to a directory to save the chain database
  - `block_mine_time` - Block period to use in developer mode (0 = mine only if transaction pending) (default: 0)
  - `accounts` - How many accoutn should be created on start (Default: `1`)
  - `notify_pid` - Internal process id that will be notified on some chain events
  - `output` - Path to logs file. If empty string passing logs will be stored into `db_path <> /out.log`. To disable logging pass `nil`

  """
  @type t :: %__MODULE__{
          type: Chain.evm_type(),
          id: Chain.evm_id() | nil,
          http_port: non_neg_integer(),
          ws_port: non_neg_integer(),
          network_id: non_neg_integer(),
          db_path: binary(),
          block_mine_time: non_neg_integer(),
          accounts: non_neg_integer(),
          output: binary,
          notify_pid: nil | pid()
        }

  defstruct type: :ganache,
            id: nil,
            http_port: 8545,
            ws_port: 8546,
            network_id: 999,
            db_path: "",
            block_mine_time: 0,
            accounts: 1,
            output: "",
            notify_pid: nil
end
