# TestChain

This is Elixir MVP implementation of Testchain as a Service.

Right now it implements this features:
 
 - Start/stop new chain (`geth|ganache`)
 - Start/Stop mining process
 - Take/revert snapshot

## Installation

As for now project requires Elixir installed + chain you want to work with.

[**Installing Elixir**](https://elixir-lang.org/install.html)

### Geth
ExTestchain uses `geth` installed in your system.

[**Installation**](https://github.com/ethereum/go-ethereum/wiki/Installing-Geth)

After this `geth` should be available in your system.

### Ganache
ExTestchain uses local ganache-cli installation.

Installing ganache locally:

```bash
cd priv/presets/ganache
npm install
```

## Building

First you need to install dependencies. For elixir project it's done using command:
```bash
mix deps.get
```

To build binary for your env follow this commands:

```bash
cd apps/cli
mix escript.build
```

It will create binary in `bin/ex_testchain`
Running binary: 

```bash
./bin/ex_testchain --help
```

## Installing globaly.
After building binary you can install in systemwise using command:
```bash
mix escript.install ./bin/ex_testchain
```

And it will become accesible from anywhere you need.

## ExTestchain CLI

Without any option CLI will start in interactive mode and will print help there.

List of available commands:

```
 -h|--help      Shows this help message
 -v|--version   Shows CLI tools versions and all other version info for system
 -s|--start     Start new chain and enter interactive mode.
```
Start new chain:

To start new chain use `-s --datadir=/some/dir` options.
Example:

```bash
./bin/ex_testchain -s --datadir=/tmp/test
```
Other start options:

```
  -t|--type       Chain type. Available options are: [geth|ganache] (default: geth)
  -a|--accounts   Amount of account needed to create on chain start (default: 1)
  --datadir       Data directory for the chain databases and keystore
  --rpcport       HTTP-RPC server listening port (default: 8545)
  --wsport        WS-RPC server listening port (default: 8546)
  --out           File where all chain logs will be streamed
  --networkid     Network identifier (integer, 1=Frontier, 2=Morden (disused), 3=Ropsten, 4=Rinkeby) (default: 999)
  --automine      Enable mining (default: disabled)
```

After starting new chain system will enter interactive mode.
Where you can type `help` for getting help.

## Logging
For now ExTestchain uses logger in debug mode and all messages will be printed to your CLI.
To omit this uncomment logger level in `apps/chain/config/config.ex`

```elixir
config :logger, level: :info
```

And recompile your binary `cd apps/cli && mix escript.build && cd -`

Happy testing ! :ghost:
