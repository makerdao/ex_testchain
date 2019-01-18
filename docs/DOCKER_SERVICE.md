# Ex Teschain

This is doc on ExTestchain behaviour into docker and future plans.

By default ExTestchain will be wrapped into Docker image `makerdao/ex_testchain:latest`

### What is ExTestchain ?

ExTestchain is service that provides you with tools and all required binaries for runnin various EVM chains on your local machine.
Mainly for testing purposes.

## Building image
For your joi there is `Makefile` with all required commands.

`make deps` - Will install all dependencies for **LOCAL** (not in docker) environment
`make build-evm` - Will build required EVM image with `geth` and `ganache`
`make build` - Will build `ex_testchain` image that you will be able to use locally
`make run` - Will run image you built locally

`make run` will use this options for your image:
```bash
docker run \
    -v /tmp/chains:/opt/chains \
    -v /tmp/snapshots:/opt/snapshots \
    --expose 4001 -p 4001:4001 \
    --expose 8500-8600 -p 8500-8600:8500-8600 \
    ex_testchain:latest
```

## Installation

You could install it from docker hub using `docker run makerdao/ex_testchain:latest` command.

Because ExTestchain could start different chains it requires lot of ports to be proxied from docker.

By default docker will expose port `4001` and set of ports for chains: `8500-8600`
So when you will run docker on your machine you will have to add `-p 4001:4001 -p 8500-8600:8500-8600`
to your `docker run` command.

If you plan to start `ganache` on port `7545` (**not in default range**) you will have to add `-p 7545:7545 --expose 7545` to your `docker run` command.

For `geth` you will need to use 2 ports (For example: `8545` for http json rpc 
and `8546` for ws connections), you don't need to add anything. 
Because ports are into default range `8500-8600`

**Note:** You couldn't omit port `4001` otherwise you wouldn't be able to control ExTestchain
For starting `geth` without any existing snapshot (or set of chain files) you can start docker using command:
```bash
$ docker run -d --name ex_testchain -p 4001:4001 -p 8500-8600:8500-8600  makerdao/ex_testchain:latest
```

After docker image will start you will be able to send commands to ExTestchain using it's [WS API](./WS_API.md).

## Existing chain data

To start ExTestchain with existing chain data from specified directory you will need:

Lets assume you already have chain data from `ganache` in `/tmp/ganache`
You have to run docker image with `-v /tmp/ganache:/var/ganache` [Docker volumes docs](https://docs.docker.com/storage/volumes/)

Example:
```bash
$ docker run -d --name ex_testchain -v /tmp/ganache:/opt/my-awesome-chain -p 4001:4001 -p 8500-8600:8500-8600 makerdao/ex_testchain:latest
```

And after docker starts send start request with `"db_path": "/opt/my-awesome-chain"` parameter.
**Note:** chain will continue running and your data might be changed !
