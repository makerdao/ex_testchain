# Ex Teschain

This is doc on ExTestchain behaviour into docker and future plans.

By default ExTestchain will be wrapped into Docker image `makerdao/ex_testchain:latest`

### What is ExTestchain ?

ExTestchain is service that provides you with tools and all required binaries for runnin various EVM chains on your local machine.
Mainly for testing purposes.

## API
ExTestchain will use special port `8080` for internal communication.
This port is exposed by default and you don't need to add `--expose 8080` to `docker run` command.

There are 2 ways of communication with ExTestchain:
  
  - REST API - basic REST API **For long running tasks you will have to check results by sending new queries**
  - WS API - Websocket based API

Both API's are JSON based.

**TBD** API description. 
For now I'll just make a simple requests for starting chain.

Example:
```
{
  "action": "start", 
  "params": {
    "id": "some-custom-chain-id-or-empty",
    "type": "geth",
    "http_port": 8545,
    "ws_port": 8546,
    "network_id": 999, // Might be omited
    "accounts": 10 // Create 10 new accounts
  },
  "requestId": "randomIdHere"
}
```

## Installation

You could install it from docker hub using `docker run makerdao/ex_testchain:latest` command.

Because ExTestchain could start different chains it requires lot of ports to be proxied from docker.
So if you plan to start `ganache` on port `7545` you will have to add `-p 7545:7545 --expose 7545` to your `docker run` command.

For `geth` you will need to use 2 ports (For example: `8545` for http json rpc and `8546` for ws connections),
You will have to add `-p 8545:8545 -p 8546:8546 --expose 8545 --expose 8546` to your `docker run` command.

**Note:** You couldn't omit port `8080` otherwise you wouldn't be able to control ExTestchain
For starting `geth` without any existing snapshot (or set of chain files) you can start docker using command:
```bash
$ docker run -d --name ex_testchain -p 8080:8080 -p 8545:8545 -p 8546:8546 --expose 8545 --expose 8546 makerdao/ex_testchain:latest
```

After docker image will start you will be able to send commands to ExTestchain using it's API.
Example:

```bash
$ curl --request POST \
       -H "Content-Type: application/json" \
       -d '{"action": "start", "params": {"type": "geth", "http_port": 8545, "ws_port": 8546, "accounts": 5}}'
       http://localhost:8080/api

{"type": "geth", "id": "17218892990927780769", "http_port": 8545, "ws_port": 8546, ....}
```

## Existing chain data

To start ExTestchain with existing chain data from specified directory you will need:

Lets assume you already have chain data from `ganache` in `/tmp/ganache`
You have to run docker image with `-v /tmp/ganache:/var/ganache` [Docker volumes docs](https://docs.docker.com/storage/volumes/)

Example:
```bash
$ docker run -d --name ex_testchain -v /tmp/ganache:/var/ganache -p 8080:8080 -p 8545:8545 --expose 8545 makerdao/ex_testchain:latest
```

And after docker starts send start request with `"db_path": "/var/ganache"` parameter.

```bash
$ curl --request POST \
       -H "Content-Type: application/json" \
       -d '{"action": "start", "params": {"type": "ganache", "db_path": "/var/ganache", "http_port": 8545, "accounts": 5}}'
       http://localhost:8080/api
```
It will start ganache chain based on your files.
**Note:** chain will continue running and your data might be changed !
