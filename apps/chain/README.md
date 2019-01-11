# Chain

Elixir application responsible of starting/controlling different chains (EVM's)
For now it coudl work with:

 - `geth` - Geth client. 
 - `ganache` - Ganache client

Application consist of N simple modules: 
 - `Chain.EVM` - behaviour that have to be implemented by any evm type (sort of interface in non Elixir)
 - `Chain.EVM.Config` - Module contain starting configuration of chian/evm
 - `Chain.EVM.Notification` - Module containing base scructure for all notifications from chains
 - `Chain` - Main module containing all basic functionality for starting/controlling chains/evms
 - `Chain.EVM.Implementation.Geth` - Geth specific functions and EVM implementation
 - `Chain.EVM.Implementation.Ganache` - Ganache implementation and specific functions

## Config
To be able to start any chain you have to pass configuration to `Chain.start/1` function.
Configuration consist of this properties:

 - `type` - evm type (`:geth`, `:ganache`) **Required**
 - `db_path` - Path where all chain data will be stored. **Required** if not exist - system will try to create it.
 - `id` - internal **unique** chain identificatior (if empty will be generated automatically)
 - `http_port` - Default HTTP JSONRPC port. (Default: `8545`)
 - `ws_port` - Default WS JSONRPC port (Default: `8546`) **For ganache it will be ignored** (`http_port` will be used)
 - `network_id` - Network ID for your chain/evm. (Default: `999`)
 - `block_mine_time` - Block period to use in developer mode (0 = mine only if transaction pending) (default: 0)
 - `accounts` - Amount of accounts need to be created on chain/evm start (Default: `1`)
 - `output` - Path to output file where all chain/evm logs will be written
 - `notify_pid` - Internal Erlang Process ID that should be notified on chain/evm event.
 - `clean_on_stop` - Clean up `db_path` after chain is stopped. (Default: `false`)
 
Example: 
```elixir
config = %Chain.EVM.Config{type: :geth, db_path: "/absolute/path/to/chain/db/folder", notify_pid: self()}
{:ok, id} = Chain.start(config)
```

It will start new geth chain on default ports using `--datadir /absolute/path/to/chain/db/folder`

In case of starting more than one chain/evm in this application be sure you changed:
 
 - `http_port`
 - `ws_port`
 - `network_id`
 - `db_path`

Otherwise chain/evm will fail to start.

## Starting/Stopping chains
It's very easy to start/stop chains here. 
Just use `{:ok, id} = Chain.start(config)` to start chain.
After calling this function if you didn't provided `id` to your config. System will generate unique id and return it in `{:ok, id}` tuple. 

To stop chain you have to use `Chain.stop(id)` function.

Example:
```elixir
iex()> config = %Chain.EVM.Config{type: :geth, db_path: "/absolute/path/to/chain/db/folder", notify_pid: self()}
iex()> {:ok, id} = Chain.start(config)
iex()> Chain.stop(id)
```

## Mining
Right now system wouldn't start mining automatically.

There 2 funtions that starts/stops mining process for chain/evm

 - `Chain.start_mine(id)` - Will start mining (might be some delay)
 - `Chain.stop_mine(id)` - Will stop mining

## Snapshots functionality
Chains/evm should be able to create/restore snaphots
Due to big differences between chains/evms creating snapshots require path where snapshot should be put
