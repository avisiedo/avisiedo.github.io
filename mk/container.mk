ifneq (,$(shell command -v podman 2>/dev/null))
DOCKER ?= podman
else
ifneq (,$(shell command -v docker 2>/dev/null))
DOCKER ?= docker
else
DOCKER ?= 
endif
endif

IMG_BASE ?= quay.io/avisied0
IMG ?= $(IMG_BASE)/blog:latest

DOCKER_CMD ?= 
DOCKER_BUILD_ARGS ?= --build-arg ARCH=$(shell uname -m)
DOCKER_DOCKERFILE ?= Dockerfile
DOCKER_ARGS ?= --rm -it -p 8000:80

##@ Container actions

.PHONY: container-build
container-build: ## Build the $IMG with $DOCKER_BUILD_ARGS for $DOCKER_DOCKERFILE
	$(DOCKER) build -t $(IMG) -f $(DOCKER_DOCKERFILE) $(DOCKER_BUILD_ARGS) .

.PHONY: container-push
container-push: ## Push image container to the registry (you have to be logged in)
	$(DOCKER) push $(IMG)

.PHONY: container-shell
container-shell: ## Open a shell in a new container
	$(DOCKER) run --rm -it --entrypoint "" $(IMG) bash

.PHONY: container-run
container-run: ## Run the container executing the $DOCKER_CMD command with $DOCKER_ARGS
	$(DOCKER) run $(DOCKER_ARGS) $(IMG) $(DOCKER_CMD)
