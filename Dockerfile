on of Alpine to use for the final image
# This should match the version of Alpine that the `elixir:1.7.2-alpine` image uses
ARG ALPINE_VERSION=3.8

FROM elixir:1.7.2-alpine AS builder

# The following are build arguments used to change variable parts of the image.
# The name of your application/release (required)
ARG APP_NAME
# The version of the application we are building (required)
ARG APP_VSN
# The environment to build with
ARG MIX_ENV=prod

ARG PORT=5412

ENV APP_NAME=${APP_NAME} \
    APP_VSN=${APP_VSN} \
    MIX_ENV=${MIX_ENV} \
    PORT=${PORT} \
    FO_SERVICE_URL=${FO_SERVICE_URL} \
    BO_SERVICE_URL=${BO_SERVICE_URL} \
    TOKEN_SERVICE_URL=${TOKEN_SERVICE_URL} \ 
    BO_USERNAME=${BO_USERNAME} \
    BO_PASSWORD=${BO_PASSWORD}
    

# By convention, /opt is typically used for applications
WORKDIR /opt/app

# This step installs all the build tools we'll need
RUN apk update && \
  apk upgrade --no-cache && \
  apk add --no-cache \
    git \
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

# From this line onwards, we're in a new image, which will be the image used in production
FROM alpine:${ALPINE_VERSION}

# The name of your application/release (required)
ARG APP_NAME

EXPOSE ${PORT}

RUN apk update && \
    apk add --no-cache \
      bash \
      openssl

ENV REPLACE_OS_VARS=true \
    APP_NAME=${APP_NAME} \
    PORT=${PORT} \
    FO_SERVICE_URL=${FO_SERVICE_URL} \
    BO_SERVICE_URL=${BO_SERVICE_URL} \
    TOKEN_SERVICE_URL=${TOKEN_SERVICE_URL} \ 
    BO_USERNAME=${BO_USERNAME} \
    BO_PASSWORD=${BO_PASSWORD}

WORKDIR /opt/app

COPY --from=builder /opt/built .

CMD trap 'exit' INT; /opt/app/bin/${APP_NAME} foreground
