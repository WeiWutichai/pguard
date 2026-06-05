# syntax=docker/dockerfile:1
# ─────────────────────────────────────────────────────────────────────────────
# pguard v2 — PRODUCTION image for the Next.js 16 web-admin.
#
# Multi-stage: pnpm build → `output: 'standalone'` (next.config.ts) → slim runtime
# copying only .next/standalone + static assets. Non-root, pinned base, HEALTHCHECK.
#
#   docker build -f infra/docker/web-admin.Dockerfile -t pguard/web-admin:0.1.0 .
# ─────────────────────────────────────────────────────────────────────────────

ARG NODE_VERSION=20

# ── deps: install workspace deps (cached on lockfile/manifest changes) ──
FROM node:${NODE_VERSION}-bookworm-slim AS deps
RUN corepack enable
WORKDIR /app/apps/web-admin
COPY apps/web-admin/package.json ./
# Use the lockfile when present (reproducible); fall back to a plain install so the
# scaffold builds before a pnpm-lock.yaml is committed. Add the lockfile to enable
# --frozen-lockfile for fully reproducible installs.
COPY apps/web-admin/pnpm-lock.yaml* ./
RUN if [ -f pnpm-lock.yaml ]; then pnpm install --frozen-lockfile; else pnpm install; fi

# ── builder: compile the standalone server bundle ──
FROM node:${NODE_VERSION}-bookworm-slim AS builder
RUN corepack enable
WORKDIR /app/apps/web-admin
COPY --from=deps /app/apps/web-admin/node_modules ./node_modules
COPY apps/web-admin/ ./
ENV NEXT_TELEMETRY_DISABLED=1
RUN pnpm build

# ── runtime: minimal Node, non-root, standalone server only ──
FROM node:${NODE_VERSION}-bookworm-slim AS runtime
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=3000 \
    HOSTNAME=0.0.0.0

# `node` is the image's built-in non-root user (uid 1000). Copy the self-contained
# server + static assets only — no source, no dev deps.
#
# web-admin is a single, non-workspace package (no root pnpm-workspace.yaml), so Next's
# outputFileTracingRoot resolves to the app dir → standalone emits a FLAT bundle:
# server.js at the root, static expected under ./.next/static. (If this ever becomes a
# real pnpm workspace, set outputFileTracingRoot to the repo root and the layout nests.)
COPY --from=builder --chown=node:node /app/apps/web-admin/.next/standalone ./
COPY --from=builder --chown=node:node /app/apps/web-admin/.next/static ./.next/static
# public/ is optional in this scaffold; copy if it exists (kept commented until added):
# COPY --from=builder --chown=node:node /app/apps/web-admin/public ./public

EXPOSE 3000
USER node

HEALTHCHECK --interval=30s --timeout=3s --start-period=15s --retries=3 \
    CMD curl -fsS "http://localhost:${PORT}/healthz" || exit 1

# Flat standalone layout: server.js sits at the image root.
CMD ["node", "server.js"]
