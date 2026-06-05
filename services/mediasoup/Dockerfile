# pguard mediasoup SFU (Node). Media plane for the calling service.
#
# Hardening (CLAUDE.md container rules + v1 follow-ups):
#  - runs as the non-root `node` user
#  - publishes ONLY the WebRTC UDP media range, never a host TCP port (the control plane is
#    reached internally by the calling service over the cluster network)
#  - the mediasoup native engine is built at image time (build deps in the builder stage only)

FROM node:20-bookworm-slim

# Build deps for the mediasoup native worker (kept minimal; this is the runtime image).
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install deps first for layer caching. `npm ci` builds the optional native engine here.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY src ./src

ENV NODE_ENV=production \
    MEDIASOUP_PORT=3011 \
    RTC_MIN_PORT=40000 \
    RTC_MAX_PORT=49999

# WebRTC media — the ONLY host-exposed surface (UDP). The control HTTP port stays internal.
EXPOSE 40000-49999/udp

USER node
CMD ["node", "src/index.js"]
