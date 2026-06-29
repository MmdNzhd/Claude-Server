#!/bin/bash
# claude-wrapper.sh -- wraps the claude CLI to inject CLAUDE_WRAPPER_PID
# Deployed to /usr/local/bin/claude (replaces the direct symlink)
# The actual Claude binary is at /usr/local/bin/claude-real
#
# Purpose: claude-hook-pre.sh uses CLAUDE_WRAPPER_PID to track active sessions
# accurately. Without this, it falls back to PPID (still works, less precise).

export CLAUDE_WRAPPER_PID=$$
unset ANTHROPIC_BASE_URL
exec /usr/local/bin/claude-real "$@"
