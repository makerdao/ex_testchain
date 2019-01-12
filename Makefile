EVM_NAME ?= ex_evm
EVM_VSN ?= v6.2.4
APP_NAME ?= ex_testchain
APP_VSN ?= 0.1.0
BUILD ?= `git rev-parse --short HEAD`
ALPINE_VERSION ?= edge
DOCKER_ID_USER ?= makerdao

help:
	@echo "$(EVM_NAME):$(EVM_VSN)-$(BUILD)"
	@echo "$(APP_NAME):$(APP_VSN)-$(BUILD)"
	@perl -nle'print $& if m{^[a-zA-Z_-]+:.*?## .*$$}' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
.PHONY: help

lint:
	@mix dialyzer --format dialyxir --quiet
	@mix credo
.PHONY: lint

docker-push:
	@echo "Pushing docker images"
	@docker tag $(EVM_NAME):$(EVM_VSN)-$(BUILD) $(DOCKER_ID_USER)/$(EVM_NAME)
	@docker push $(DOCKER_ID_USER)/$(EVM_NAME)
	@docker tag $(APP_NAME):$(APP_VSN)-$(BUILD) $(DOCKER_ID_USER)/$(APP_NAME)
	@docker push $(DOCKER_ID_USER)/$(APP_NAME)
.PHONY: docker-push

deps: ## Load all required deps for project
	@mix do deps.get, deps.compile
	@cd priv/presets/ganache-cli
	@npm install --no-package-lock
	@cd -
.PHONY: deps

build-evm: ## Build the Docker image for geth/ganache/other evm
	@docker build -f ./Dockerfile.evm \
		--build-arg ALPINE_VERSION=$(ALPINE_VERSION) \
		-t $(EVM_NAME):$(EVM_VSN)-$(BUILD) \
		-t $(EVM_NAME):latest .

.PHONY: build-evm

build: ## Build elixir application with testchain and WS API
	@docker build \
		--build-arg ALPINE_VERSION=$(ALPINE_VERSION) \
		--build-arg APP_NAME=$(APP_NAME) \
        --build-arg APP_VSN=$(APP_VSN) \
		--build-arg EVM_IMAGE=$(EVM_NAME):latest \
        -t $(APP_NAME):$(APP_VSN)-$(BUILD) \
        -t $(APP_NAME):latest .	
.PHONY: build

run-evm: ## Run evm image after build
	@docker run --rm -it \
			--expose 8545 \
			-p 8545:8545 \
			${EVM_NAME}:latest
.PHONY: run-evm

run: ## Run the app in Docker
	@docker run \
		-v /tmp/chains:/opt/chains \
		-v /tmp/snapshots:/opt/snapshots \
		--expose 4000 -p 4000:4000 \
		--expose 8500-8600 -p 8500-8600:8500-8600 \
		--rm -it $(APP_NAME):latest
.PHONY: run
