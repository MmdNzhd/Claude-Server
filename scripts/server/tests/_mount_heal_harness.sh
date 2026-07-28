#!/bin/bash
# _mount_heal_harness.sh — shared asserts for mount/heal hard suites
# shellcheck disable=SC2034
set -u

ASSERTS=0
FAILS=0
SUITE="${SUITE_NAME:-unknown}"

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_SERVER="$(cd "$_here/.." && pwd)"

pass() {
    ASSERTS=$((ASSERTS + 1))
}
fail() {
    ASSERTS=$((ASSERTS + 1))
    FAILS=$((FAILS + 1))
    echo "FAIL [$SUITE]: $*" >&2
}

assert_true() {
    local msg="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        pass
    else
        fail "$msg"
    fi
}

assert_false() {
    local msg="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        fail "$msg (expected false)"
    else
        pass
    fi
}

assert_eq() {
    local msg="$1" got="$2" want="$3"
    if [ "$got" = "$want" ]; then
        pass
    else
        fail "$msg got='$got' want='$want'"
    fi
}

assert_file_has() {
    local msg="$1" file="$2" pat="$3"
    if [ -f "$file" ] && grep -qE "$pat" "$file"; then
        pass
    else
        fail "$msg ($file !~ /$pat/)"
    fi
}

assert_file_lacks() {
    local msg="$1" file="$2" pat="$3"
    if [ -f "$file" ] && grep -qE "$pat" "$file"; then
        fail "$msg ($file has /$pat/)"
    else
        pass
    fi
}

assert_ge() {
    local msg="$1" n="$2" min="$3"
    if [ "$n" -ge "$min" ] 2>/dev/null; then
        pass
    else
        fail "$msg n=$n min=$min"
    fi
}

finish_suite() {
    echo "ASSERTS=$ASSERTS FAILS=$FAILS SUITE=$SUITE"
    if [ "$FAILS" -gt 0 ]; then
        return 1
    fi
    if [ "$ASSERTS" -lt 50 ]; then
        echo "FAIL [$SUITE]: ASSERTS=$ASSERTS < 50" >&2
        return 1
    fi
    return 0
}
