#!/usr/bin/env bash
set -euo pipefail
bash -n "$HOME/.local/bin/claude-mount"
echo bash_n_ok
python3 - <<'PY'
from pathlib import Path
t = Path.home().joinpath('.local/bin/claude-mount').read_text()
broken = "${rpath//'/''}"
escaped = "${rpath//\\'/\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'}"  # wrong
# construct exactly
broken = "${" + "rpath//'/" + "''}"
# simpler counts
b = t.count("${rpath//'/'")  # prefix of broken
# exact broken token
broken_exact = "${rpath//" + "'" + "/" + "''" + "}"
escaped_exact = "${rpath//" + "\\'" + "/" + "\\'\\'" + "}"
print('broken_exact', t.count(broken_exact))
print('escaped_exact', t.count(escaped_exact))
print('has_emit_def', '_emit_git_hide_warn() {' in t)
if t.count(broken_exact) != 0:
    raise SystemExit('still has broken form')
if t.count(escaped_exact) < 3:
    raise SystemExit('escaped form missing')
PY
awk '/^case /{exit}{print}' "$HOME/.local/bin/claude-mount" > /tmp/cmf.sh
# shellcheck disable=SC1091
source /tmp/cmf.sh
declare -F _emit_git_hide_warn >/dev/null
echo EMIT_OK
_emit_git_hide_warn $'GIT_HIDE:skip\r' || true
echo emit_call_ok
"$HOME/.local/bin/claude-mount" check deploy || true
echo check_done
# if not mounted, try up quickly
if ! "$HOME/.local/bin/claude-mount" check deploy >/dev/null 2>&1; then
  CLAUDE_TRUSTED_TUNNEL=1 timeout 40 "$HOME/.local/bin/claude-mount" up deploy
fi
"$HOME/.local/bin/claude-mount" check deploy
echo LIVE_MOUNT_OK
