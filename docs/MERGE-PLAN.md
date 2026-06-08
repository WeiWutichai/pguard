# Integration / Merge Plan — pguard PR stack (v2, updated 2026-06-05)

> Verified topology after PR #6. Goal: collapse 6 open PRs into a single green `main`.
> The tree is mostly linear; there are exactly **two conflict surfaces**: `PROGRESS.md`
> (append-only, union-resolve) and **`services/api-gateway/src/main.rs`** (two backend
> siblings both add to the gateway router — keep both). Run these yourself.

## Verified topology

```
main (821bda2 · bootstrap)
└─ feat/v2-scaffold-notification (3a0b62c · scaffold + notification + mobile base + tokens)
   ├─ feat/identity-booking      (PR #2 · all backend services)
   │  ├─ feat/c5.1-observability (PR #4) → feat/c5.2-pdpa (PR #5)   ← backend chain (linear)
   │  └─ feat/booking-status-ws  (PR #6 · gateway WS edge)          ← sibling off #2
   └─ feat/mobile-phase2         (PR #3 · mobile)                   ← off scaffold
```

## Conflict map (verified)

| Branches that meet | Files | How to resolve |
|---|---|---|
| c5.2-chain ↔ booking-status-ws | `services/api-gateway/src/main.rs` | **keep BOTH** — c5.1's OTel/metrics layer + the WS route registration |
| any backend ↔ mobile / ↔ ws | `PROGRESS.md` | **union** — keep all Completed-log rows |

Everything else is disjoint (Rust backend vs Dart mobile; the two siblings touch different gateway files except `main.rs`).

## Order (do now)

### 1. Backend chain → main  (PR #2 → #4 → #5 in one)
`c5.2-pdpa` is a descendant of #2 and #4, so merging it brings all three.
```bash
git checkout main
git merge --no-ff feat/c5.2-pdpa
cargo build --workspace && cargo clippy --workspace --all-targets -D warnings && cargo test --workspace   # gate
```

### 2. booking-status-ws → main  (PR #6)
```bash
git merge --no-ff feat/booking-status-ws
# CONFLICTS: services/api-gateway/src/main.rs (keep both additions) + PROGRESS.md (union)
git add services/api-gateway/src/main.rs PROGRESS.md && git commit --no-edit
cargo test --workspace   # gate (gateway must compile with BOTH the OTel wiring and the WS route)
```

### 3. mobile → main  (PR #3)
```bash
git merge --no-ff feat/mobile-phase2
# CONFLICT: PROGRESS.md only (union)
git add PROGRESS.md && git commit --no-edit
(cd apps/mobile && flutter analyze && flutter test)   # gate
```

### 4. Verify unified main
```bash
cargo test --workspace            # backend green
(cd apps/mobile && flutter test)  # mobile green
```

## Then branch next work off the new main
- C5.2 **data-export** (§19) → `feat/c5.2-data-export`
- C5.3 DB scaling, C5.4 security sweep → stacked off main, one backend track at a time
- More mobile screens → off main

## Cleanup
```bash
# stray untracked Flutter build artifacts from the mobile branch (heads-up from PR #6):
git clean -ndx apps/mobile    # review first (dry-run), then drop -n to delete *.g.dart, .claude/
git branch -d feat/identity-booking feat/c5.1-observability feat/c5.2-pdpa feat/booking-status-ws feat/mobile-phase2 feat/v2-scaffold-notification   # after PRs merged
git worktree prune            # removes stale wf_* worktrees
```

## Rules
- If any gate fails, or a conflict appears in a file NOT in the conflict map above, **STOP and report**.
- Do not push to a remote or delete branches until confirmed.
- `cargo test --workspace` + `flutter test` must both be green on the final `main`.
- Don't modify `../guard-dispatch/`.

## Why now
6 PRs is the ceiling before this gets painful. The only real code conflict is one gateway
file (two route additions). Merge → then data-export / C5.3 / C5.4 off a clean main, serial on the backend.
