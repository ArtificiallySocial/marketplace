---
name: cleanup-claude-procs
description: Detect and clean up stray processes spawned by Claude Code sessions (orphaned node, playwright, chromium, tmux panes, background shells)
triggers:
  - cleanup claude
  - stray processes
  - kill leftover
  - orphan processes
  - claude procs
argument-hint: "[--dry-run | --yes]"
---

# cleanup-claude-procs

## Purpose

Find and clean up processes left behind by prior Claude Code sessions — orphaned `node`/`claude` CLIs, headless browsers from Playwright MCP, lingering tmux panes from `omc-teams`, and background shells started via `run_in_background` whose parent has exited.

## When to Activate

- User says "clean up stray processes", "kill leftover claude", "something's eating CPU", "orphan processes"
- After a crashed or force-killed Claude session
- System feels sluggish and user suspects Claude-spawned leftovers

## Workflow

### 1. Identify current session to protect

Capture the PID tree of THIS running Claude instance so we never kill ourselves:

```bash
SELF_PID=$$
SELF_PPID=$(ps -o ppid= -p $$ | tr -d ' ')
# Walk up to find the claude process anchoring this session
SELF_TREE=$(pstree -p $SELF_PPID 2>/dev/null | grep -oE '\([0-9]+\)' | tr -d '()' | sort -u)
echo "Protected PIDs: $SELF_PID $SELF_PPID $SELF_TREE"
```

### 2. Scan for candidate stray processes

Gather candidates across these categories. Use `ps -eo pid,ppid,etimes,user,command` and filter.

**Claude CLI / node orphans**
```bash
ps -eo pid,ppid,etimes,command | awk '
  /claude-code|claude --|\.claude\/|@anthropic-ai\/claude-code/ && $2 == 1 {print}
'
```

**Playwright / headless Chromium from MCP**
```bash
ps -eo pid,ppid,etimes,command | grep -E 'playwright|chrome.*--headless|chromium.*--remote-debugging' | grep -v grep
```

**OMC background shells / tmux panes**
```bash
tmux list-sessions 2>/dev/null | grep -E 'omc-|claude-' || true
ps -eo pid,ppid,etimes,command | grep -E '\.omc/|omc-teams|ralph|ultrawork' | grep -v grep
```

**Orphaned `run_in_background` shells (ppid=1, long etime, bash/sh)**
```bash
ps -eo pid,ppid,etimes,command | awk '$2 == 1 && $3 > 300 && /\/bin\/(ba)?sh/ {print}'
```

**Orphaned long-running CLI tails/follows owned by the user (ppid=1)**

Anything that Claude kicked off via `run_in_background` (log tails, `watch`, `jobs --watch`, `gh run watch`, `amplify ... --watch`, `kubectl logs -f`, etc.) can outlive its parent shell and end up as a PPID=1 orphan. These are easy to miss because they're not `node`/`chromium`.

```bash
ps -eo pid,ppid,etimes,user,command | awk -v u="$USER" '
  $2 == 1 && $3 > 300 && $4 == u &&
  /aws logs tail|--follow|tail -[fF]|watch |gh run watch|kubectl .*-f|amplify .*--watch|docker logs -f/ {print}
'
```

### 3. Filter out protected PIDs

Remove any PID in the current session's tree from the candidate list.

### 4. Present findings

Show a table: PID | PPID | Age | Category | Command (truncated). Example:

```
PID     PPID  AGE    CATEGORY        COMMAND
12345   1     2h14m  claude-orphan   node /home/user/.nvm/.../claude-code
12892   1     47m    playwright      chromium --headless --remote-debugging-port=...
13044   1     3h01m  bg-shell        /bin/bash -c 'npm run test:e2e'
```

If list is empty: report "No stray Claude-spawned processes found." and exit.

### 5. Confirm before killing

Unless `--yes` was passed, ask: "Kill these N processes? (yes/no/select)"
- `yes` → kill all
- `no` → exit
- `select` → prompt per PID

Unless `--dry-run` (then print what would be killed and exit).

### 6. Kill with escalation

```bash
for PID in $TARGETS; do
  kill -TERM "$PID" 2>/dev/null
done
sleep 2
for PID in $TARGETS; do
  if kill -0 "$PID" 2>/dev/null; then
    kill -KILL "$PID" 2>/dev/null
    echo "SIGKILL: $PID"
  else
    echo "SIGTERM ok: $PID"
  fi
done
```

### 7. Clean tmux remnants

```bash
tmux list-sessions 2>/dev/null | awk -F: '/^omc-|^claude-/ {print $1}' | while read s; do
  tmux kill-session -t "$s" && echo "Killed tmux session: $s"
done
```

### 8. Report summary

```
✓ Terminated 3 processes (2 TERM, 1 KILL)
✓ Closed 1 tmux session (omc-team-abc123)
```

## Safety Rules

- **Never kill the current session's PID tree.** Always compute `SELF_TREE` first.
- **Never kill PID 1, systemd, sshd, login shells, or the user's interactive zsh/bash.**
- **Age threshold:** default minimum etime of 60s to avoid racing a just-spawned process.
- **Default to dry-run-then-confirm** — require explicit `yes` or `--yes` flag for actual kills.
- If `pstree` is unavailable, fall back to walking `/proc/<pid>/status` PPid chain.

## Examples

```
/oh-my-claudecode:cleanup-claude-procs
/oh-my-claudecode:cleanup-claude-procs --dry-run
/oh-my-claudecode:cleanup-claude-procs --yes
```

## Notes

- MCP servers (playwright, filesystem, etc.) respawn on next session — killing them is safe between sessions but may break a parallel running Claude instance. Check for other active Claude sessions with `pgrep -af claude-code | grep -v $$` and warn the user.
- On Raspberry Pi / low-memory hosts, orphaned chromium is the most common culprit.
- If a process refuses SIGKILL it's likely in uninterruptible sleep (D state) — report it but don't loop.
