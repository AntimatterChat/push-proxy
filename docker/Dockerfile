# Antimatter push proxy, built from source.
#
#   docker build -f docker/Dockerfile -t antimatter-push-proxy .
#
# The configuration is read from /antimatter-push-proxy/config/antimatter-push-proxy.json
# (mount your own over it) and the Apple/Firebase credentials it points to are usually
# mounted under /antimatter-push-proxy/certs. See README.md.

ARG GO_VERSION=1.26

FROM --platform=${BUILDPLATFORM} golang:${GO_VERSION}-alpine AS builder
ARG TARGETOS
ARG TARGETARCH
# Version information, passed by `make docker-build`; left at their defaults otherwise.
ARG GIT_VERSION=devel
ARG BUILD_HASH=unknown
ARG BUILD_TAG_LATEST=unknown
ARG BUILD_TAG_CURRENT=unknown
ARG GIT_TREESTATE=unknown
ARG BUILD_DATE=unknown

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY main.go ./
COPY internal ./internal
COPY server ./server
RUN PKG=github.com/AntimatterChat/push-proxy/internal/version \
  && CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -trimpath \
    -ldflags "-s -w \
      -X '${PKG}.gitVersion=${GIT_VERSION}' \
      -X '${PKG}.buildHash=${BUILD_HASH}' \
      -X '${PKG}.buildTagLatest=${BUILD_TAG_LATEST}' \
      -X '${PKG}.buildTagCurrent=${BUILD_TAG_CURRENT}' \
      -X '${PKG}.gitTreeState=${GIT_TREESTATE}' \
      -X '${PKG}.buildDate=${BUILD_DATE}'" \
    -o /out/antimatter-push-proxy .

FROM alpine:3

# hadolint ignore=DL3018
RUN apk add --no-cache ca-certificates tzdata

WORKDIR /antimatter-push-proxy
COPY --from=builder /out/antimatter-push-proxy bin/antimatter-push-proxy
COPY config/antimatter-push-proxy.sample.json config/antimatter-push-proxy.sample.json
COPY config/antimatter-push-proxy.sample.json config/antimatter-push-proxy.json
COPY docker/entrypoint /usr/local/bin/entrypoint

RUN mkdir -p certs logs && chown -R nobody:nobody /antimatter-push-proxy

USER nobody
ENV PUSH_PROXY=/antimatter-push-proxy/bin/antimatter-push-proxy

EXPOSE 8066
VOLUME ["/antimatter-push-proxy/config", "/antimatter-push-proxy/certs"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD wget -q -O /dev/null http://127.0.0.1:8066/version || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint"]
