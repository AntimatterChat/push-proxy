# ====================================================================================
# Antimatter push proxy
#
#   make build          build the binaries for every platform into ./dist
#   make package        build and pack each binary with the sample config into a .tar.gz
#   make docker-build   build the Docker image (from source, see docker/Dockerfile)
#   make test / lint    run the tests / golangci-lint and hadolint
#   make run            run locally with config/antimatter-push-proxy.json
# ====================================================================================

APP_NAME          := antimatter-push-proxy
GO_MODULE         := github.com/AntimatterChat/push-proxy

APP_COMMIT        := $(shell git rev-parse HEAD 2>/dev/null)
# A release tag (vX.Y.Z) when building one, dev-<sha> otherwise.
APP_VERSION       ?= $(shell git describe --abbrev=0 --exact-match --tags 2>/dev/null || echo dev-$(APP_COMMIT))
APP_VERSION_NO_V  := $(patsubst v%,%,$(APP_VERSION))

GIT_VERSION       ?= $(shell git describe --tags --always --dirty 2>/dev/null)
GIT_TREESTATE     := $(if $(shell git status --porcelain 2>/dev/null),dirty,clean)
BUILD_DATE        := $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
BUILD_HASH        := $(shell git rev-parse --short HEAD 2>/dev/null)
BUILD_TAG_LATEST  := $(shell git describe --tags --match 'v*' --abbrev=0 2>/dev/null)
BUILD_TAG_CURRENT := $(shell git tag --points-at HEAD 2>/dev/null)

MAKEFLAGS     += --no-builtin-rules
.DEFAULT_GOAL := help

## Go
GO                  ?= go
GO_OUT_BIN_DIR      := ./dist
GO_BUILD_PLATFORMS  ?= linux-amd64 linux-arm64 freebsd-amd64
GO_BUILD_OPTS       += -trimpath
GO_TEST_OPTS        += -timeout=180s
VERSION_PKG         := $(GO_MODULE)/internal/version
GO_LDFLAGS          += -X "$(VERSION_PKG).gitVersion=$(GIT_VERSION)"
GO_LDFLAGS          += -X "$(VERSION_PKG).buildHash=$(BUILD_HASH)"
GO_LDFLAGS          += -X "$(VERSION_PKG).buildTagLatest=$(BUILD_TAG_LATEST)"
GO_LDFLAGS          += -X "$(VERSION_PKG).buildTagCurrent=$(BUILD_TAG_CURRENT)"
GO_LDFLAGS          += -X "$(VERSION_PKG).gitTreeState=$(GIT_TREESTATE)"
GO_LDFLAGS          += -X "$(VERSION_PKG).buildDate=$(BUILD_DATE)"

## Docker
DOCKER              ?= docker
DOCKER_FILE         ?= ./docker/Dockerfile
DOCKER_IMAGE        ?= $(APP_NAME)
DOCKER_PLATFORMS    ?= linux/amd64,linux/arm64
DOCKER_IMAGE_GOLINT ?= golangci/golangci-lint:v2.12.2
DOCKER_IMAGE_LINT   ?= hadolint/hadolint:v2.12.0
DOCKER_BUILD_ARGS   := \
	--build-arg GIT_VERSION="$(GIT_VERSION)" \
	--build-arg BUILD_HASH="$(BUILD_HASH)" \
	--build-arg BUILD_TAG_LATEST="$(BUILD_TAG_LATEST)" \
	--build-arg BUILD_TAG_CURRENT="$(BUILD_TAG_CURRENT)" \
	--build-arg GIT_TREESTATE="$(GIT_TREESTATE)" \
	--build-arg BUILD_DATE="$(BUILD_DATE)"

# ====================================================================================

.PHONY: help
help: ## to get help
	@echo "Usage:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	awk 'BEGIN {FS = ":.*?## "}; {printf "  make %-16s %s\n", $$1, $$2}'

.PHONY: build
build: $(addprefix go-build/$(APP_NAME)-,$(GO_BUILD_PLATFORMS)) ## to build the binaries into ./dist

go-build/%:
	@target="$*"; platform="$${target#$(APP_NAME)-}"; \
	echo "go build $$platform"; \
	CGO_ENABLED=0 GOOS="$${platform%%-*}" GOARCH="$${platform#*-}" \
	$(GO) build $(GO_BUILD_OPTS) -ldflags '$(GO_LDFLAGS)' -o $(GO_OUT_BIN_DIR)/$* .

.PHONY: package
package: build ## to pack each binary with the sample config into ./dist/*.tar.gz
	@for file in $(GO_OUT_BIN_DIR)/$(APP_NAME)-*; do \
		case "$$file" in *.tar.gz) continue;; esac; \
		target=$$(basename $$file); \
		rm -rf $(GO_OUT_BIN_DIR)/$${target}_temp; \
		mkdir -p $(GO_OUT_BIN_DIR)/$${target}_temp/bin $(GO_OUT_BIN_DIR)/$${target}_temp/config; \
		cp config/antimatter-push-proxy.sample.json $(GO_OUT_BIN_DIR)/$${target}_temp/config/; \
		echo $(APP_VERSION) > $(GO_OUT_BIN_DIR)/$${target}_temp/config/build.txt; \
		cp README.md LICENSE.txt NOTICE.txt $(GO_OUT_BIN_DIR)/$${target}_temp/; \
		mv $$file $(GO_OUT_BIN_DIR)/$${target}_temp/bin/$(APP_NAME); \
		tar -czf $(GO_OUT_BIN_DIR)/$${target}.tar.gz -C $(GO_OUT_BIN_DIR) --transform "s,^$${target}_temp,$(APP_NAME)," $${target}_temp; \
		rm -rf $(GO_OUT_BIN_DIR)/$${target}_temp; \
		echo "packaged $(GO_OUT_BIN_DIR)/$${target}.tar.gz"; \
	done

.PHONY: run
run: ## to run locally (reads config/antimatter-push-proxy.json)
	$(GO) run $(GO_BUILD_OPTS) .

.PHONY: test
test: ## to run the tests
	$(GO) test $(GO_TEST_OPTS) ./...

.PHONY: vet
vet: ## to run go vet
	$(GO) vet ./...

.PHONY: lint
lint: go-lint docker-lint ## to lint the Go code and the Dockerfile

.PHONY: go-lint
go-lint: ## to lint the Go code with golangci-lint (in Docker)
	$(DOCKER) run --rm -v $(CURDIR):/app -w /app $(DOCKER_IMAGE_GOLINT) golangci-lint run ./...

.PHONY: docker-lint
docker-lint: ## to lint the Dockerfile with hadolint (in Docker)
	$(DOCKER) run --rm -i $(DOCKER_IMAGE_LINT) < $(DOCKER_FILE)

.PHONY: go-mod-check
go-mod-check: ## to check that go.mod and go.sum are tidy
	$(GO) mod tidy
	git --no-pager diff --exit-code go.mod go.sum

.PHONY: docker-build
docker-build: ## to build the Docker image $(DOCKER_IMAGE):$(APP_VERSION_NO_V) for this machine
	$(DOCKER) build $(DOCKER_BUILD_ARGS) -f $(DOCKER_FILE) -t $(DOCKER_IMAGE):$(APP_VERSION_NO_V) .

.PHONY: docker-buildx
docker-buildx: ## to build (and with PUSH=1 push) a multi-platform image, e.g. DOCKER_IMAGE=ghcr.io/antimatterchat/push-proxy
	$(DOCKER) buildx build $(DOCKER_BUILD_ARGS) --platform $(DOCKER_PLATFORMS) -f $(DOCKER_FILE) \
		-t $(DOCKER_IMAGE):$(APP_VERSION_NO_V) $(if $(PUSH),--push,) .

.PHONY: clean
clean: ## to remove ./dist
	rm -rf $(GO_OUT_BIN_DIR)
