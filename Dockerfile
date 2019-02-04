# The version of Alpine to use for the final image
ARG ALPINE_VERSION=edge
ARG EVM_IMAGE=makerdao/ex_evm:latest

FROM alpine:${ALPINE_VERSION} AS builder

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
    erlang \
    erlang-runtime-tools \
    elixir \
    git \
    bash \
    build-base && \
  mix local.rebar --force && \
  mix local.hex --force

# This copies our app source code into the build container
COPY . .

RUN mix do deps.get, deps.compile, compile

RUN \
  mkdir -p /opt/built && \
  mix release --verbose && \
  cp _build/${MIX_ENV}/rel/${APP_NAME}/releases/${APP_VSN}/${APP_NAME}.tar.gz /opt/built && \
  cd /opt/built && \
  tar -xzf ${APP_NAME}.tar.gz && \
  rm ${APP_NAME}.tar.gz


#######
#
# Running container
#
#######
FROM ${EVM_IMAGE}

# The name of your application/release (required)
ARG APP_NAME=${APP_NAME}
ARG PORT=4000

EXPOSE ${PORT}
EXPOSE 8500-8600

WORKDIR /opt/app

RUN apk update && \
    apk add --no-cache \
      bash \
      openssl

ENV REPLACE_OS_VARS=true \
    APP_NAME=${APP_NAME} \
    PORT=${PORT}

COPY --from=builder /opt/built .

COPY ./priv/presets/geth/account_password /opt/built/priv/presets/geth/account_password
COPY ./priv/presets/ganache/wrapper.sh /opt/built/priv/presets/ganache/wrapper.sh

CMD trap 'exit' INT; /opt/app/bin/${APP_NAME} foreground
