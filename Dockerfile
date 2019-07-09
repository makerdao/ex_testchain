# The version of Alpine to use for the final image
ARG ALPINE_VERSION=edge
ARG EVM_IMAGE=makerdao/ex_evm:latest

FROM elixir:1.9.0-alpine as builder

# The following are build arguments used to change variable parts of the image.
# The name of your application/release (required)
ARG APP_NAME=ex_testchain
# The version of the application we are building (required)
ARG APP_VSN=0.1.0
# The environment to build with
ARG MIX_ENV=prod

ENV APP_NAME=${APP_NAME} \
    APP_VSN=${APP_VSN} \
    MIX_ENV=${MIX_ENV}

# By convention, /opt is typically used for applications
WORKDIR /opt/app

# This step installs all the build tools we'll need
RUN apk update && \
  apk upgrade --no-cache && \
  apk add --no-cache \
    git \
    bash \
    build-base && \
  mix local.rebar --force && \
  mix local.hex --force

# This copies our app mix.exs and mix.lock source code into the build container
COPY mix.* ./
COPY apps/chain/mix.* ./apps/chain/
COPY apps/json_rpc/mix.* ./apps/json_rpc/
COPY apps/storage/mix.* ./apps/storage/

RUN mix do deps.get, deps.compile

# This copies our app source code into the build container
COPY . .
RUN mix compile

RUN \
  mkdir -p /opt/built && \
  mix release && \
  cp -R _build/${MIX_ENV}/rel/${APP_NAME}/ /opt/built


#######
#
# Running container
#
#######
FROM ${EVM_IMAGE}

# The name of your application/release (required)
ARG APP_NAME=${APP_NAME}

EXPOSE 8500-8600

WORKDIR /opt/app

RUN apk update && \
    apk add --no-cache \
      bash \
      openssl

ENV APP_NAME=${APP_NAME} \
    MIX_ENV=prod \
    FRONT_URL="ex-testchain.local" \
    RELEASE_COOKIE="W_cC]7^rUeVZc|}$UL{@&1sQwT3}p507mFlh<E=/f!cxWI}4gpQx7Yu{ZUaD0cuK"

COPY --from=builder /opt/built/${APP_NAME} .

COPY ./priv/presets/geth/account_password /opt/built/priv/presets/geth/account_password
COPY ./priv/presets/ganache/wrapper.sh /opt/built/priv/presets/ganache/wrapper.sh

CMD trap 'exit' INT; /opt/app/bin/${APP_NAME} start
