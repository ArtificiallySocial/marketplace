---
name: system-check
description: Quick health check of the local development environment — memory, load, disk, Claude processes — and auto-invoke cleanup-claude-procs if signs of leftover Claude sessions are detected.
triggers:
  - system check
  - health check
  - check system
  - how's the system
  - dev environment status
argument-hint: "[--verbose]"
---

# system-check

## Purpose

Give a fast, readable snapshot of the development environment's health and flag whether any remediation is needed. Combines standard Linux commands (`free`, `uptime`, `df`, `ps`) with a targeted look for leftover Claude-spawned processes, and decides on its own whether to escalate to `/cleanup-claude-procs`.

## When to Activate

- User says "system check", "health check", "how's the system looking", "is everything OK"
- Before/after a long-running task when the user wants to confirm the box is healthy
- After multiple Claude sessions have been run and the user suspects cruft

## Workflow

### 1. Gather core metrics (run in parallel)

```bash
free -h
uptime
df -h / /tmp 2>/dev/null | grep -v tmpfs
# Top 5 memory consumers
ps -eo pid,user,%mem,%cpu,etimes,command --sort=-%mem | head -6
# Claude-family process count (excluding this session's tree)
pgrep -af 'claude-code|@anthropic-ai/claude-code|playwright-mcp|chromium.*--headless' | wc -l
# Load vs. core count
nproc
# Local IP address
hostname -I | awk '{print $1}'
```

### 2. Interpret thresholds

Evaluate each signal and classify **OK / WARN / ALERT**:

| Signal | OK | WARN | ALERT |
|---|---|---|---|
| Available memory | > 25% | 10–25% | < 10% |
| Swap used | < 25% | 25–60% | > 60% with free RAM < 20% |
| Load avg (1-min) / cores | < 0.7 | 0.7–1.5 | > 1.5 |
| Disk / usage | < 80% | 80–90% | > 90% |
| Stray claude/playwright procs (ppid=1) | 0 | 1–2 | 3+ |
| Uptime | any | > 30 days | n/a |

### 3. Decide on escalation

- **ALERT on stray procs** → automatically invoke `/cleanup-claude-procs` (dry-run first, then confirm with user before killing).
- **WARN on stray procs** → report them and *suggest* `/cleanup-claude-procs`, don't auto-run.
- **ALERT on memory + stray procs present** → same as above but lead with the memory concern.
- **ALERT on disk** → list largest dirs under `$HOME` and `/tmp` with `du -sh` (top 5).
- **OK across the board** → one-line "all green" summary.

### 4. Report format

Use a compact, scannable format:

```
SYSTEM CHECK — 2026-04-15 09:31
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
IP:      192.168.1.100
Memory:  3.0 GiB available / 4.0 GiB total    [OK]
Swap:    640 MiB / 2.0 GiB used               [OK]
Load:    0.23 0.10 0.03 (4 cores)             [OK]
Disk /:  42% used                             [OK]
Uptime:  1 day, 11h
Stray claude procs: 0                         [OK]

→ All green. Nothing to do.
```

For a WARN/ALERT, add a **Recommendations** section with the specific next action and offer to run it.

### 5. Offer follow-ups

Depending on findings, suggest:
- `/cleanup-claude-procs` — for stray processes
- `du -sh ~/* | sort -h` — for disk pressure
- `sudo reboot` — if uptime > 30 days AND swap pressure high
- Nothing — if everything is green

## Examples

```
/oh-my-claudecode:system-check
/oh-my-claudecode:system-check --verbose
```

## Notes

- Thresholds are tuned for low-memory hosts (4 GB RAM default).
- Never kills anything on its own — escalation to `/cleanup-claude-procs` still goes through that skill's own confirmation flow.
- If `pgrep` shows Claude procs but they all belong to the *current* session (check PPID chain via `pstree`), don't count them as stray.
- Keep the report to one screen. Verbose mode (`--verbose`) may add per-process detail and full `df` output.
