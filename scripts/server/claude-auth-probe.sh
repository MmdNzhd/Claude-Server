#!/bin/bash
# claude-auth-probe — test CLAUDE_CODE_OAUTH_TOKEN against Anthropic API; append JSONL log
# Usage: sudo claude-auth-probe.sh [source-label]

set -euo pipefail

LIB="/usr/local/lib/claude-server/claude-auth-lib.py"
[ -f "$LIB" ] || LIB="$(dirname "$0")/claude-auth-lib.py"

SOURCE="${1:-cron}"
exec python3 "$LIB" probe "$SOURCE"
