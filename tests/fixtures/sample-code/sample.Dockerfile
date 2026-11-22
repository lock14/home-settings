# syntax=docker/dockerfile:1
# Solarized Dark TrueColor Showcase: Multi-Stage Production Containerfile

ARG GO_VERSION=1.24.1
ARG ALPINE_VERSION=3.21
ARG BUILD_COMMIT="4b825dc"

FROM golang:${GO_VERSION}-alpine${ALPINE_VERSION} AS builder

ENV CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=amd64 \
    GOTOOLCHAIN=local

WORKDIR /workspace

COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download -x

COPY cmd/ ./cmd/
COPY internal/ ./internal/

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    set -eux; \
    if [ -z "${BUILD_COMMIT}" ]; then \
        echo "missing BUILD_COMMIT" >&2; \
        exit 1; \
    fi; \
    go build \
        -trimpath \
        -ldflags="-s -w -X main.commit=${BUILD_COMMIT}" \
        -o /out/solarized-gateway \
        ./cmd/solarized-gateway

FROM alpine:${ALPINE_VERSION} AS runtime

ARG SERVICE_PORT=8080
ARG METRICS_PORT=9090

LABEL org.opencontainers.image.title="solarized-gateway" \
      org.opencontainers.image.vendor="Solarized Systems" \
      org.opencontainers.image.licenses="MIT"

ENV APP_ENV="production" \
    LOG_FORMAT="json" \
    LISTEN_PORT=${SERVICE_PORT} \
    MAX_CONNECTIONS=4096 \
    TLS_ENABLED=true

RUN set -eux; \
    apk add --no-cache ca-certificates tzdata curl; \
    addgroup -g 10001 -S gateway; \
    adduser -u 10001 -S -G gateway -H -s /sbin/nologin gateway; \
    mkdir -p /etc/solarized /var/lib/solarized; \
    chown -R gateway:gateway /etc/solarized /var/lib/solarized

WORKDIR /var/lib/solarized

COPY --from=builder --chown=10001:10001 /out/solarized-gateway /usr/local/bin/solarized-gateway

USER 10001:10001

EXPOSE 8080/tcp 9090/tcp

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -fsS "http://127.0.0.1:${LISTEN_PORT}/healthz" || exit 1

ENTRYPOINT ["/usr/local/bin/solarized-gateway"]
CMD ["--config", "/etc/solarized/gateway.yaml", "--port", "8080"]
