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

[Installation](https://github.com/ethereum/go-ethereum/wiki/Installing-Geth)
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
