#!/bin/bash
# test-project-rpath.sh — laptop path validation helpers (Mac client)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../git-mode.sh
. "$ROOT/git-mode.sh"
export GIT_MODE_LAPTOP_OS=mac

fail=0
assert() {
    if ! eval "$2"; then
        echo "FAIL: $1" >&2
        fail=1
    fi
}

assert 'D:/temp incompatible on Mac' '! laptop_rpath_compatible "D:/temp" mac'
assert '/Users/x ok on Mac' 'laptop_rpath_compatible "/Users/x/Projects" mac'
assert '/Users incompatible on Windows' '! laptop_rpath_compatible "/Users/x" windows'
assert 'D:/ ok on Windows' 'laptop_rpath_compatible "D:/Smart" windows'
assert 'hint for D:/ on Mac' '[ "$(laptop_rpath_os_hint "D:/temp" mac)" = "Windows only" ]'
assert 'connect-ui has no Enter=project hint' '! grep -qiE "Enter = .*project|Enter = Temp" "$ROOT/connect-ui.sh"'
assert 'connect.sh empty enter continues' 'grep -A1 "if \[ -z \"\$choice\" \]" "$ROOT/mac/connect.sh" | grep -q continue'


assert 'D:temp blocked on Mac' '! laptop_rpath_compatible "D:temp" mac'
assert 'whitespace D:/ blocked on Mac' '! laptop_rpath_compatible "  D:/temp  " mac'
assert 'whitespace choice treated empty' '[ -z "$(printf "   " | sed "s/^[[:space:]]*//;s/[[:space:]]*$//")" ]'


sample=$'ai|Ai|D:/x|/home/smart/mounts/ai\nclaude-server|CS|/Users/x/y|/home/smart/mounts/cs'
filtered="$(filter_mounts_for_laptop "$sample")"
assert 'filter hides Windows paths on Mac' '[ "$filtered" = "claude-server|CS|/Users/x/y|/home/smart/mounts/cs" ]'
assert 'skipped count on Mac' '[ "$(count_skipped_mounts_for_laptop "$sample")" = "1" ]'

if [ "$fail" -eq 0 ]; then
    echo 'OK test-project-rpath.sh'
else
    exit 1
fi
