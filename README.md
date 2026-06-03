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
