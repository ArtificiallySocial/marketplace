#!/usr/bin/env bash
# pushover.sh - Send push notifications via the Pushover API
#
# Required environment variables:
#   PUSHOVER_TOKEN - Your Pushover application API token
#   PUSHOVER_USER  - Your Pushover user or group key
#
# Usage:
#   pushover.sh [options] <message>
#   echo "message" | pushover.sh [options]
#
# Options:
#   -t, --title <title>        Message title
#   -p, --priority <-2..2>     Priority level (default: 0)
#   -s, --sound <name>         Notification sound (e.g. pushover, cosmic, siren)
#   -d, --device <name>        Target a specific device (default: all)
#   -u, --url <url>            Supplementary URL
#   -U, --url-title <title>    Title for the supplementary URL
#   -H, --html                 Render message as HTML
#   -m, --monospace            Render message in monospace font
#       --ttl <seconds>        Auto-delete after N seconds
#       --retry <seconds>      Priority 2: retry interval (min 30)
#       --expire <seconds>     Priority 2: max retry window (max 10800)
#       --timestamp <epoch>    Custom Unix timestamp
#   -a, --attachment <file>    Attach an image file
#   -q, --quiet                Suppress success output (errors still print)
#   -h, --help                 Show this help
#
# Exit codes:
#   0  success
#   1  usage / missing args
#   2  missing credentials
#   3  API error
#   4  missing dependency

set -euo pipefail

print_help() {
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
}

die() {
  echo "pushover: $1" >&2
  exit "${2:-1}"
}

command -v curl >/dev/null 2>&1 || die "curl is required" 4

TITLE=""
PRIORITY=""
SOUND=""
DEVICE=""
URL=""
URL_TITLE=""
HTML=""
MONOSPACE=""
TTL=""
RETRY=""
EXPIRE=""
TIMESTAMP=""
ATTACHMENT=""
QUIET=0
MESSAGE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--title)       TITLE="$2"; shift 2 ;;
    -p|--priority)    PRIORITY="$2"; shift 2 ;;
    -s|--sound)       SOUND="$2"; shift 2 ;;
    -d|--device)      DEVICE="$2"; shift 2 ;;
    -u|--url)         URL="$2"; shift 2 ;;
    -U|--url-title)   URL_TITLE="$2"; shift 2 ;;
    -H|--html)        HTML=1; shift ;;
    -m|--monospace)   MONOSPACE=1; shift ;;
    --ttl)            TTL="$2"; shift 2 ;;
    --retry)          RETRY="$2"; shift 2 ;;
    --expire)         EXPIRE="$2"; shift 2 ;;
    --timestamp)      TIMESTAMP="$2"; shift 2 ;;
    -a|--attachment)  ATTACHMENT="$2"; shift 2 ;;
    -q|--quiet)       QUIET=1; shift ;;
    -h|--help)        print_help; exit 0 ;;
    --)               shift; MESSAGE="${MESSAGE:+$MESSAGE }$*"; break ;;
    -*)               die "unknown option: $1" 1 ;;
    *)                MESSAGE="${MESSAGE:+$MESSAGE }$1"; shift ;;
  esac
done

# If no message on CLI, read from stdin (if piped)
if [[ -z "$MESSAGE" ]] && [[ ! -t 0 ]]; then
  MESSAGE="$(cat)"
fi

[[ -z "$MESSAGE" ]] && die "message is required (pass as arg or via stdin)" 1
[[ -z "${PUSHOVER_TOKEN:-}" ]] && die "PUSHOVER_TOKEN env var is not set" 2
[[ -z "${PUSHOVER_USER:-}" ]]  && die "PUSHOVER_USER env var is not set" 2

if [[ "$PRIORITY" == "2" ]]; then
  [[ -z "$RETRY" ]]  && RETRY=60
  [[ -z "$EXPIRE" ]] && EXPIRE=3600
fi

if [[ -n "$HTML" && -n "$MONOSPACE" ]]; then
  die "--html and --monospace are mutually exclusive" 1
fi

if [[ -n "$ATTACHMENT" && ! -r "$ATTACHMENT" ]]; then
  die "attachment not readable: $ATTACHMENT" 1
fi

args=(
  --silent --show-error
  --form-string "token=$PUSHOVER_TOKEN"
  --form-string "user=$PUSHOVER_USER"
  --form-string "message=$MESSAGE"
)
[[ -n "$TITLE" ]]     && args+=(--form-string "title=$TITLE")
[[ -n "$PRIORITY" ]]  && args+=(--form-string "priority=$PRIORITY")
[[ -n "$SOUND" ]]     && args+=(--form-string "sound=$SOUND")
[[ -n "$DEVICE" ]]    && args+=(--form-string "device=$DEVICE")
[[ -n "$URL" ]]       && args+=(--form-string "url=$URL")
[[ -n "$URL_TITLE" ]] && args+=(--form-string "url_title=$URL_TITLE")
[[ -n "$HTML" ]]      && args+=(--form-string "html=1")
[[ -n "$MONOSPACE" ]] && args+=(--form-string "monospace=1")
[[ -n "$TTL" ]]       && args+=(--form-string "ttl=$TTL")
[[ -n "$RETRY" ]]     && args+=(--form-string "retry=$RETRY")
[[ -n "$EXPIRE" ]]    && args+=(--form-string "expire=$EXPIRE")
[[ -n "$TIMESTAMP" ]] && args+=(--form-string "timestamp=$TIMESTAMP")
[[ -n "$ATTACHMENT" ]] && args+=(--form "attachment=@$ATTACHMENT")

response="$(curl "${args[@]}" https://api.pushover.net/1/messages.json)" || die "curl failed" 3

if [[ "$response" == *'"status":1'* ]]; then
  [[ "$QUIET" -eq 0 ]] && echo "$response"
  exit 0
else
  echo "pushover API error: $response" >&2
  exit 3
fi
