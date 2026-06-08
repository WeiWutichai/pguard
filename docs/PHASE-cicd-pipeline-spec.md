# CI/CD — GitHub Actions (build/test all stacks + image push) — work spec

> For Claude Code (Terminal A). The repo has **no `.github/workflows/`**. Add CI (build + lint +
> test every stack on PR/push) and CD (build per-service prod images → ghcr.io). This replaces
> the manual per-merge verification we've been doing. **Adapt the v1 patterns** documented in
> CLAUDE.md (downcase owner, per-service `context`, matrix). Branch off freshly synced main.
> Don't merge; don't touch `../guard-dispatch/`.

## Setup
```bash
git checkout main && git pull          # 14f687c
git worktree add ../pguard-cicd -b feat/cicd-pipeline main
cd ../pguard-cicd
```

## Scope

### A. `ci.yml` — on every push + PR to main
Jobs (use the SAME commands the slices verified locally):
- **Rust:** `cargo fmt --check` · `cargo clippy --all-targets --all-features -D warnings` · `cargo build --workspace` · `cargo test --workspace`. (Cache cargo registry + target.) Provide the test-time env the gated tests need OR run only the hermetic suite in CI and gate the DB/NATS/Redis tests behind a services-up job (Postgres 17 + NATS + Redis service containers + apply `contracts/db/migrations/*`).
- **Mobile (Flutter):** `flutter pub get` · `dart run build_runner build --delete-conflicting-outputs` · `flutter analyze` · `flutter test`.
- **web-admin (Next.js):** `pnpm install --frozen-lockfile` · `pnpm lint` · `pnpm exec tsc --noEmit` · `pnpm build`.
- **mediasoup (Node):** `npm ci` · `npm run lint` · `npm test`.
- **Compose validate:** `docker compose -f infra/docker/docker-compose.prod.yml config` (with dummy required secrets) — catches compose drift.
- Pin action versions; `fail-fast: false` across the stack jobs so one red stack doesn't mask the others.

### B. `deploy.yml` — on push to main (build + push images)
- **Matrix** over the 12 Rust services + `mediasoup` + `web-admin`. Build each Dockerfile, push to `ghcr.io/<owner>/pguard/<svc>:latest` + `:<git-sha>`.
- **Downcase the owner** (`WeiWutichai` → lowercase) via `tr '[:upper:]' '[:lower:]'` into `$GITHUB_ENV` before using it as the ghcr path — uppercase breaks `docker buildx push` (the v1 footgun, CLAUDE.md).
- **Per-service `context`**: Rust services build from repo root `.` (their Dockerfile uses full workspace paths via `rust-service.Dockerfile` + `BIN`/`APP_PORT` build-args); `mediasoup` uses `context: services/mediasoup`; `web-admin` its own context. `fail-fast: false`.
- Deploy job: keep it `if: false` (manual) like v1 — or a documented staging SSH step — but **don't** wire real secrets/hosts in this slice. Just prove the image build+push matrix.
- Use `permissions: packages: write` + `GITHUB_TOKEN` for ghcr login.

### C. Make CI green
- Run the jobs' logic locally where possible; fix any real gap they expose (e.g. a service that needs an env var to build, a flaky gated test). If the gated Rust tests can't run without infra, split: a fast hermetic `cargo test` job (always) + a `cargo test -- --include-ignored`/DB-gated job with service containers + migrations applied.

## Definition of Done
- `ci.yml` + `deploy.yml` present, valid YAML, action versions pinned.
- CI jobs use the exact verified commands; the matrix in deploy covers all 14 images with correct contexts + downcased owner.
- Locally dry-run what you can (`act` optional; at minimum `docker compose config`, the build/lint/test commands) — document anything CI-only.
- Update `PROGRESS.md` (tick CI/CD + Completed-log row) · run the review agents (code-reviewer + architecture-guardian; security pass on the workflow permissions/secrets) · own PR off main · **don't merge**.

## Reference (read-only)
- Adapt from v1 (cite paths): `../guard-dispatch/.github/workflows/{ci.yml,deploy.yml}`. CLAUDE.md (pguard) "CI/CD Pipeline" + the Do-NOT items about `${{ github.repository_owner }}` casing, `tailscale/github-action@v4`, per-service `context`, `${IMAGE_PREFIX:?}`. Build args: `infra/docker/rust-service.Dockerfile` (`BIN`, `APP_PORT`). The 12 Rust service names + ports: `infra/docker/docker-compose.prod.yml`.
