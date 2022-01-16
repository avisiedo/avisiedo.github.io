DRAFTS ?= --drafts

# https://github.com/operator-framework/operator-sdk/blob/master/Makefile#L189
.DEFAULT_GOAL := help
.PHONY: help
help: ## Show this help screen.
	@echo 'Usage: make <OPTIONS> ... <TARGETS>'
	@echo ''
	@echo 'Available targets are:'
	@echo ''
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

include mk/container.mk

##@ General actions

:PHONY: build
build: ## Build the site at _site directory
	cobalt build $(DRAFTS)

.PHONY: serve
serve: ## Serve and watch the content
	cobalt serve $(DRAFTS)

clean: ## Clean generated contents
	cobalt clean
