#!/usr/bin/env bash
# laptop-exec - run commands on the developer laptop via reverse SSH tunnel.
# Faster than SSHFS for scan, git, build, and bulk I/O.
#
# Usage:
#   laptop-exec status
#   laptop-exec path [-p PROJECT]
#   laptop-exec count [-p PROJECT]
#   laptop-exec run  [-p PROJECT] -- <command...>
#   laptop-exec git  [-p PROJECT] -- <git-args...>
#   laptop-exec rg   [-p PROJECT] <pattern>
#   laptop-exec test
#
# Requires connect.bat/sh session (reverse tunnel alive).

set -euo pipefail

CONNECT_CONF="$HOME/.claude-connect.conf"
CONF_DIR="$HOME/.claude-mounts.d"
KEY="$HOME/.ssh/claude_laptop"
KNOWN_HOSTS="$HOME/.ssh/known_hosts_claude_mount"

LAPTOP_USER=""
TUNNEL_PORT=""
LAPTOP_OS="windows"
ACTIVE_MOUNT=""
GIT_MODE="hide"

_die() { echo "laptop-exec: $*" >&2; exit 1; }

_load_global() {
    GIT_MODE="hide"
    LAPTOP_OS="windows"
    if [ -f "$CONNECT_CONF" ]; then
        while IFS='=' read -r k v; do
            v="${v#\"}"; v="${v%\"}"
            case "$k" in
                LAPTOP_USER) LAPTOP_USER="$v" ;;
                TUNNEL_PORT) TUNNEL_PORT="$v" ;;
                GIT_MODE|git_mode) GIT_MODE="$v" ;;
                LAPTOP_OS|laptop_os) LAPTOP_OS="$v" ;;
                ACTIVE_MOUNT|active_mount) ACTIVE_MOUNT="$v" ;;
            esac
        done < "$CONNECT_CONF"
    fi
    [ -n "$TUNNEL_PORT" ] || TUNNEL_PORT=$((20000 + $(id -u)))
    case "${GIT_MODE,,}" in
        server|on|yes|1|slow) GIT_MODE="server" ;;
        *) GIT_MODE="hide" ;;
    esac
    case "${LAPTOP_OS,,}" in
        mac|darwin|osx) LAPTOP_OS="mac" ;;
        *) LAPTOP_OS="windows" ;;
    esac
}

_load_project() {
    local project_id="$1"
    local conf="$CONF_DIR/${project_id}.conf"
    [ -f "$conf" ] || _die "unknown project '$project_id' (no $conf)"
    REMOTE_PATH=""
    LOCAL_PATH=""
    while IFS='=' read -r k v; do
        v="${v#\"}"; v="${v%\"}"
        case "$k" in
            rpath|REMOTE_PATH) REMOTE_PATH="$v" ;;
            lpath|LOCAL_PATH) LOCAL_PATH="$v" ;;
        esac
    done < "$conf"
    REMOTE_PATH="${REMOTE_PATH//\\//}"
    [ -n "$REMOTE_PATH" ] || _die "no remote path in $conf"
}

_laptop_ssh() {
    ssh -n -o BatchMode=yes -o ConnectTimeout=10 \
        -o ServerAliveInterval=5 -o ServerAliveCountMax=3 \
        -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$KNOWN_HOSTS" \
        -o ControlMaster=no -o ControlPath=none \
        -i "$KEY" -p "$TUNNEL_PORT" "${LAPTOP_USER}@127.0.0.1" \
        "$@"
}

# Windows accepts forward slashes; normalize so backslashes are not eaten by SSH.
_normalize_arg() {
    printf '%s' "${1//\\//}"
}

# Detect .git.server-session vs .git per project (hide mode only applies to active mount).
_detect_git_dir() {
    local rpath="$1"
    local win_path="${rpath//\//\\}"
    local out=""
    out=$(_laptop_ssh "cmd /c \"if exist ${win_path}\\.git.server-session\\HEAD (echo .git.server-session) else if exist ${win_path}\\.git\\HEAD (echo .git) else (echo none)\"" 2>/dev/null | tr -d '\r' | head -1)
    printf '%s' "$out"
}

_run_in_project() {
    local rpath="$1"
    shift
    if [ "$LAPTOP_OS" = "mac" ]; then
        local cmd=""
        printf -v cmd '%q ' "$@"
        _laptop_ssh "bash -lc 'cd $(printf '%q' "$rpath") && $cmd'"
        return
    fi
    local win_path="${rpath//\//\\}"
    local cmdline="" arg norm
    for arg in "$@"; do
        norm="$(_normalize_arg "$arg")"
        case "$norm" in
            *[\"^\&\|\<\>\(\)]*|*\ *|*\'*|*/*)
                cmdline="${cmdline} \"${norm//\"/\\\"}\""
                ;;
            *)
                cmdline="${cmdline} ${norm}"
                ;;
        esac
    done
    cmdline="${cmdline# }"
    _laptop_ssh "cmd /c \"cd /d ${win_path} && ${cmdline}\""
}

_git_invoke() {
    local rpath="$1"
    shift
    local git_dir
    if [ "$GIT_MODE" = "server" ]; then
        _run_in_project "$rpath" git "$@"
        return
    fi
    git_dir="$(_detect_git_dir "$rpath")"
    case "$git_dir" in
        .git.server-session|.git)
            _run_in_project "$rpath" git --git-dir="$git_dir" --work-tree=. "$@"
            ;;
        none)
            _die "no git repository on laptop for $rpath"
            ;;
        *)
            _die "unexpected git dir state: $git_dir"
            ;;
    esac
}

_parse_project_flag() {
    PROJECT_ID=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -p|--project)
                [ $# -ge 2 ] || _die "missing value for $1"
                PROJECT_ID="$2"
                shift 2
                ;;
            --)
                shift
                break
                ;;
            *)
                break
                ;;
        esac
    done
    REMAINING=("$@")
}

_require_session() {
    _load_global
    [ -n "$LAPTOP_USER" ] || _die "no connect session - run connect.bat/sh first"
}

_resolve_project() {
    local pid="${PROJECT_ID:-$ACTIVE_MOUNT}"
    [ -n "$pid" ] || _die "no project (use -p or connect with a project)"
    _load_project "$pid"
}

_cmd_status() {
    _load_global
    echo "tunnel_port:  ${TUNNEL_PORT}"
    echo "laptop_user:  ${LAPTOP_USER:-<unset>}"
    echo "laptop_os:    ${LAPTOP_OS}"
    echo "active_mount: ${ACTIVE_MOUNT:-<none>}"
    echo "git_mode:     ${GIT_MODE}"
    if [ -z "$LAPTOP_USER" ]; then
        echo "tunnel:       DOWN (no connect session)"
        exit 1
    fi
    if [ "$LAPTOP_OS" = "mac" ]; then
        _laptop_ssh true >/dev/null 2>&1 && echo "tunnel:       UP" || { echo "tunnel:       DOWN"; exit 1; }
    else
        _laptop_ssh cmd /c exit 0 >/dev/null 2>&1 && echo "tunnel:       UP" || { echo "tunnel:       DOWN"; exit 1; }
    fi
}

_cmd_path() {
    _parse_project_flag "$@"
    _require_session
    _resolve_project
    echo "$REMOTE_PATH"
}

_cmd_count() {
    _parse_project_flag "$@"
    _require_session
    _resolve_project
    if [ "$LAPTOP_OS" = "mac" ]; then
        _run_in_project "$REMOTE_PATH" find . -type f | wc -l
    else
        local win_path="${REMOTE_PATH//\//\\}"
        _laptop_ssh "cmd /c \"cd /d ${win_path} && dir /s /b /a-d 2>nul\"" | wc -l
    fi
}

_cmd_read() {
    _parse_project_flag "$@"
    [ "${#REMAINING[@]}" -eq 1 ] || _die "usage: laptop-exec read [-p PROJECT] <file>"
    _require_session
    _resolve_project
    local file="${REMAINING[0]}"
    file="${file//\\//}"
    if [ "$LAPTOP_OS" = "mac" ]; then
        _run_in_project "$REMOTE_PATH" cat "$file"
    else
        local win_path="${REMOTE_PATH//\//\\}"
        local win_file="${file//\//\\}"
        _laptop_ssh "cmd /c \"cd /d ${win_path} && type ${win_file}\""
    fi
}

_cmd_run() {
    _parse_project_flag "$@"
    [ "${#REMAINING[@]}" -gt 0 ] || _die "usage: laptop-exec run [-p PROJECT] -- <command...>"
    _require_session
    _resolve_project
    _run_in_project "$REMOTE_PATH" "${REMAINING[@]}"
}

_cmd_git() {
    _parse_project_flag "$@"
    [ "${#REMAINING[@]}" -gt 0 ] || _die "usage: laptop-exec git [-p PROJECT] -- <git-args...>"
    _require_session
    _resolve_project
    _git_invoke "$REMOTE_PATH" "${REMAINING[@]}"
}

_cmd_rg() {
    _parse_project_flag "$@"
    [ "${#REMAINING[@]}" -gt 0 ] || _die "usage: laptop-exec rg [-p PROJECT] <pattern>"
    _require_session
    _resolve_project
    local pattern="${REMAINING[0]}"
    if [ "$LAPTOP_OS" = "mac" ]; then
        _run_in_project "$REMOTE_PATH" rg "$pattern" "${REMAINING[@]:1}"
        return
    fi
    _run_in_project "$REMOTE_PATH" findstr /s /m /c:"${pattern}" "*.*"
}

_cmd_test() {
    local pass=0 fail=0
    _check() {
        local name="$1"
        shift
        local out rc
        out=$("$@" 2>&1) || true
        rc=$?
        if [ "$rc" -ne 0 ]; then
            echo "FAIL  $name (exit $rc)"
            fail=$((fail + 1))
            return
        fi
        if grep -qiE '^(fatal:|FAIL |cannot find the path|not recognized as|syntax of the command)' <<<"$out"; then
            echo "FAIL  $name"
            fail=$((fail + 1))
            return
        fi
        if [ -z "$out" ] && [[ "$name" == rg* ]]; then
            echo "FAIL  $name (empty)"
            fail=$((fail + 1))
            return
        fi
        echo "PASS  $name"
        pass=$((pass + 1))
    }
    echo "laptop-exec self-test"
    _check "status" laptop-exec status
    _check "git status (active)" laptop-exec git -- status
    _check "read CLAUDE.md" laptop-exec read CLAUDE.md
    _check "read backslash path" laptop-exec read "scripts/server/laptop-exec.sh"
    _check "rg pattern" laptop-exec rg laptop-exec
    _check "run dotnet" laptop-exec run -- dotnet --version
    if [ -f "$CONF_DIR/review.conf" ]; then
        _check "git review project" laptop-exec git -p review -- status
    fi
    echo "----"
    echo "pass=$pass fail=$fail"
    [ "$fail" -eq 0 ]
}

_usage() {
    cat <<'EOF'
laptop-exec - run commands on laptop (fast path for scan/git/build)

Commands:
  status                     tunnel + session info
  path  [-p PROJECT]         print laptop path for project
  count [-p PROJECT]           file count on laptop (fast)
  read  [-p PROJECT] FILE    print file contents from laptop
  run   [-p PROJECT] -- CMD    run shell command in project dir
  git   [-p PROJECT] -- ARGS   run git in project dir on laptop
  rg    [-p PROJECT] PATTERN   search files on laptop (all files)
  test                       run self-test suite

Default project: ACTIVE_MOUNT from connect session.
Requires connect.bat/sh running (reverse tunnel).
EOF
}

main() {
    local cmd="${1:-}"
    [ -n "$cmd" ] || { _usage; exit 1; }
    shift
    case "$cmd" in
        status) _cmd_status "$@" ;;
        path)   _cmd_path "$@" ;;
        count)  _cmd_count "$@" ;;
        read)   _cmd_read "$@" ;;
        run)    _cmd_run "$@" ;;
        git)    _cmd_git "$@" ;;
        rg)     _cmd_rg "$@" ;;
        test)   _cmd_test "$@" ;;
        -h|--help|help) _usage ;;
        *) _die "unknown command '$cmd' (try: laptop-exec --help)" ;;
    esac
}

main "$@"
