# pguard

Real-time Security Guard Dispatch Platform — v2 of guard-dispatch.

This repo is currently a **bootstrapping skeleton**. The full structure gets built in Phase 0–5 per `../guard-dispatch/v2-audit/06-migration-plan.md`. For now it holds:

- `CLAUDE.md` — architecture spec + decisions
- `.claude/` — Claude Code environment (hooks, agents, agent-memory, skills install)

## Quick orientation

```
pguard/
├── README.md                ← you are here
├── CLAUDE.md                ← architecture, decisions, do/don't rules
├── pguard-brief.md          ← 3-phase plan for Claude Code CLI
├── audit-revisions.md       ← Part A revisions (✓ done) + Part B Phase 0.5 brief
├── v1-audit/                ← 7 audit files + role-access raw report
│   ├── 00-overview.md       ← executive summary + risk table
│   ├── 01-current-state.md  ← service inventory, coupling, debt
│   ├── 02-issues.md         ← architectural issues ranked
│   ├── 03-security.md       ← JWT/PIN/audit gaps + top 15 risks
│   ├── 04-tests.md          ← coverage gaps (P0 critical)
│   ├── 05-recommendations.md ← per-service redesign vs port + §5.7 ops maturity
│   ├── 06-migration-plan.md ← 6-phase strangler-fig (+ Phase 0.5)
│   └── role-access-audit-raw.md ← ground-truth role audit
├── docs/
│   ├── ROLE_MATRIX.md       ← source of truth for admin/guard/customer permissions
│   └── reviews/             ← HTML visual artifacts
│       ├── role-access-matrix.html
│       └── frontend-backend-permission-mismatch.html
├── redesign-pguard/         ← Claude Design output (40 HTML pages, hi-fi mockups)
│   └── project/pguard/      ← Design System.html, Web Admin Live Map.html,
│                              Mobile - Active Standby.html, Coverage Matrix.html, ...
└── .claude/
    ├── settings.json        ← hooks config
    ├── INSTALL-SKILLS.md    ← how to install 9arm-skills
    ├── hooks/
    │   ├── pre-tool.sh      ← blocks destructive bash commands
    │   └── post-edit.sh     ← auto fmt/clippy/dart-analyze + unwrap warning
    ├── agents/              ← 4 subagents (code-reviewer, security-reviewer, test-writer, architecture-guardian)
    └── agent-memory/        ← per-agent knowledge bases (project-specific)
```

## Getting started

```bash
cd /Users/nest/Documents/pguard
claude   # opens Claude Code in this folder
```

Then in Claude Code:

```
Read CLAUDE.md, then read ../guard-dispatch/v2-audit/00-overview.md to understand the v1 → pguard migration plan.
```

## Install skills

This project uses [9arm-skills](https://github.com/thananon/9arm-skills) (4 skills: debug-mantra, post-mortem, scrutinize, management-talk). One-time install:

```bash
npx skills add thananon/9arm-skills
```

See `.claude/INSTALL-SKILLS.md` for details.

## Reference

- v1 source: `../guard-dispatch/` (read-only reference — do not modify)
- v1 audit: `../guard-dispatch/v2-audit/` (7 files)
- v1 audit revisions brief: `../guard-dispatch/audit-revisions.md`
- Claude Design output: separate project (hi-fi mockups for all surfaces)

## License

TBD
