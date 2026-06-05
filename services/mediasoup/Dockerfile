# syntax=docker/dockerfile:1
# pguard mediasoup SFU (Node). Media plane for the calling service.
#
# Hardening (CLAUDE.md container rules + v1 follow-ups):
#  - multi-stage: the native-build toolchain (python3, build-essential) stays in the
#    builder; the runtime image carries only node_modules + src (no compilers)
#  - runs as the non-root `node` user
#  - pinned base (no :latest)
#  - publishes ONLY the WebRTC UDP media range, never a host TCP port (the control
#    plane is reached internally by the calling service over the cluster network)
#  - HEALTHCHECK hits the internal control-plane /health
#
# Build context is this directory (services/mediasoup):
#   docker build -t pguard/mediasoup:0.1.0 services/mediasoup

ARG NODE_VERSION=20

# ── builder: compile the mediasoup native worker ──
FROM node:${NODE_VERSION}-bookworm-slim AS builder
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 build-essential \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
# `npm ci` builds the optional native engine here, against the committed lockfile.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# ── runtime: slim, non-root, no build toolchain ──
FROM node:${NODE_VERSION}-bookworm-slim AS runtime
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app

COPY --from=builder --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node package.json ./
COPY --chown=node:node src ./src

ENV NODE_ENV=production \
    MEDIASOUP_PORT=3011 \
    RTC_MIN_PORT=40000 \
    RTC_MAX_PORT=49999

# WebRTC media — the ONLY host-exposed surface (UDP). The control HTTP port stays internal.
EXPOSE 40000-49999/udp

USER node

# Control-plane /health (internal port 3011); never published to the host.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD curl -fsS "http://localhost:${MEDIASOUP_PORT}/health" || exit 1

CMD ["node", "src/index.js"]
