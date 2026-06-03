# Install Skills for pguard

pguard uses [thananon/9arm-skills](https://github.com/thananon/9arm-skills) — 4 general-purpose engineering skills:

| Skill | Purpose |
|---|---|
| `debug-mantra` | Four-mantra debugging discipline (reproduce → trace → falsify → cross-reference) before any fix |
| `post-mortem` | Canonical engineering record for fixed bugs (root cause, mechanism, fix, validation, slip-through) |
| `scrutinize` | Outsider-perspective end-to-end review of plans/PRs/code |
| `management-talk` | Rewrite engineer content for management audiences (JIRA, Slack, email, async standup) |

## One-time install (recommended)

```bash
npx skills add thananon/9arm-skills
```

This installs the skills into `~/.claude/skills/` so they're available across all Claude Code projects on this machine.

## Alternative — clone-and-symlink (for skill authors)

```bash
git clone https://github.com/thananon/9arm-skills.git ~/code/9arm-skills
cd ~/code/9arm-skills
./scripts/link-skills.sh
```

## Verify installed

```bash
./scripts/list-skills.sh
```

Or in Claude Code session: type `/` and `debug-mantra` should autocomplete.

## When to use which skill

- **Before fixing a bug:** invoke `debug-mantra` — forces reproduce + trace before patching
- **After fixing a bug:** invoke `post-mortem` — produces canonical engineering record (gold for the 58 BUG-XXX comments from v1 audit; should reduce future BUG accumulation)
- **Before merging a non-trivial PR:** invoke `scrutinize` — independent end-to-end review, catches "looks right but does the wrong thing"
- **Writing a stakeholder update:** invoke `management-talk` — converts engineer-to-engineer prose into channel-appropriate format

## How these complement pguard's custom agents

| Custom agent (this repo) | Generic skill (9arm) | Relationship |
|---|---|---|
| `architecture-guardian` | `scrutinize` | guardian enforces rules; scrutinize asks "is this even the right problem?" |
| `code-reviewer` | `scrutinize` | code-reviewer is project-specific; scrutinize is generalist |
| `security-reviewer` | — | security-reviewer is unique to pguard; no overlap |
| `test-writer` | `debug-mantra` | when a test fails, run debug-mantra; when adding tests, use test-writer |
| — | `post-mortem` | every closed bug should produce a post-mortem entry |
| — | `management-talk` | for stakeholder updates and status reports |

Together: agents = project-specific enforcement; skills = general engineering discipline.
