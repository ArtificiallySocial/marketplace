---
name: pushover
description: Send push notifications to your phone/desktop via the Pushover API using the bundled pushover.sh helper
triggers:
  - pushover
  - push notification
  - notify phone
  - send push
  - alert me
argument-hint: "[options] <message>"
---

# Pushover Skill

## Purpose

Send push notifications to Pushover-registered devices (phones, tablets, desktop) via the Pushover HTTP API. Useful for:
- Notifying the user when long-running tasks finish (builds, deploys, test suites)
- Alerting on errors or critical events
- Sending links, results, or quick status messages to the user's device

This skill wraps `pushover.sh`, a self-contained bash helper colocated in this skill directory.

## Prerequisites

The helper reads credentials from environment variables — set these once in `~/.zshrc` (or equivalent):

```bash
export PUSHOVER_TOKEN="your_application_api_token"
export PUSHOVER_USER="your_user_or_group_key"
```

- Get an application token: https://pushover.net/apps/build
- Your user key is shown on your Pushover dashboard

If `PUSHOVER_TOKEN` or `PUSHOVER_USER` is unset, the script exits with code 2 and a clear error.

## When to Activate

Activate this skill when the user asks to:
- "Send me a push notification when X finishes"
- "Notify my phone about Y"
- "Pushover me the result"
- "Alert me when the build is done"

Also use it proactively at the end of long-running background tasks **if the user has explicitly asked to be notified on completion**. Do not send unsolicited notifications.

## Workflow

1. **Verify credentials exist** — check `$PUSHOVER_TOKEN` and `$PUSHOVER_USER` are set. If not, instruct the user to export them.
2. **Compose the message** — pick a clear title and concise body. Use priority 1 only for things the user actually wants to interrupt quiet hours; use priority 0 (default) otherwise.
3. **Invoke the helper** at `${CLAUDE_PLUGIN_ROOT}/skills/pushover/pushover.sh`.
4. **Check exit code** — on failure, report the error; do not silently retry.

## Usage

### Basic message
```bash
"${CLAUDE_PLUGIN_ROOT}/skills/pushover/pushover.sh" "Build finished successfully"
```

### With a title and higher priority
```bash
"${CLAUDE_PLUGIN_ROOT}/skills/pushover/pushover.sh" \
  --title "CI" \
  --priority 1 \
  "Deploy to prod succeeded"
```

### Include a clickable link
```bash
"${CLAUDE_PLUGIN_ROOT}/skills/pushover/pushover.sh" \
  --title "PR ready" \
  --url "https://github.com/foo/bar/pull/42" \
  --url-title "View PR #42" \
  "Review requested"
```

### Monospace body (good for logs / diffs)
```bash
tail -n 5 build.log | "${CLAUDE_PLUGIN_ROOT}/skills/pushover/pushover.sh" \
  --title "Build tail" --monospace
```

### Emergency priority (repeats until acknowledged)
```bash
"${CLAUDE_PLUGIN_ROOT}/skills/pushover/pushover.sh" \
  --priority 2 --retry 60 --expire 3600 \
  --title "PROD DOWN" "API health check failing"
```

### Attach a screenshot
```bash
"${CLAUDE_PLUGIN_ROOT}/skills/pushover/pushover.sh" \
  --title "Visual diff" \
  --attachment /tmp/screenshot.png \
  "Regression detected on homepage"
```

## Options Reference

| Flag | Description |
|------|-------------|
| `-t, --title` | Message title (default: app name) |
| `-p, --priority` | `-2` silent · `-1` low · `0` normal · `1` high · `2` emergency |
| `-s, --sound` | Override sound (e.g. `pushover`, `cosmic`, `siren`, `none`) |
| `-d, --device` | Target a specific device name; omit for all |
| `-u, --url` | Supplementary URL |
| `-U, --url-title` | Title for the URL |
| `-H, --html` | Render message as HTML |
| `-m, --monospace` | Render message in monospace |
| `--ttl` | Auto-delete message after N seconds |
| `--retry` | Priority 2: retry interval (min 30s, default 60) |
| `--expire` | Priority 2: max retry window (max 10800s, default 3600) |
| `--timestamp` | Custom Unix timestamp |
| `-a, --attachment` | Attach an image file |
| `-q, --quiet` | Suppress success output |
| `-h, --help` | Show help |

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Usage error (missing/invalid arguments) |
| 2 | Missing `PUSHOVER_TOKEN` or `PUSHOVER_USER` |
| 3 | Pushover API error (message printed to stderr) |
| 4 | Missing `curl` dependency |

## Priority Guidance

- **Default to `0`** (normal). Respects the user's quiet hours.
- Use **`1`** only when the user explicitly asks to "alert me" or for genuinely interrupting events.
- Use **`2`** (emergency, repeats until acknowledged) only when the user explicitly asks for it — e.g. "page me if prod is down."
- Use **`-1` or `-2`** for low-value info the user wants logged but not buzzed about.

## Notes

- The helper uses `--form-string` so messages with special characters (including `@`, `$`, newlines) are safe.
- Free-tier Pushover allows 10,000 messages/month per app token — be thoughtful about loops.
- Credentials are never written to disk by this skill; they live only in the environment.
- The API endpoint is `https://api.pushover.net/1/messages.json` — HTTPS required.
