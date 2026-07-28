#!/bin/bash
# deploy-laptop-exec.sh - redeploy SSH-first laptop-exec to server + all users
#
# Hardening (2026-07-28 agent-pain fixes):
# - Source of truth = laptop disk via `laptop-exec read` (mount/SSHFS may be
#   STALE or not the active project; Windows MCP writes can inject CRLF).
# - Prefer LE stage over CLIENT_BUNDLE (stale auto-update pins old paste).
# - Never install a file onto itself (set -e used to abort mid-deploy).
# - Strip CRLF on every staged .sh/.py before install + verify markers.
set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
ok() { echo -e "  ${GREEN}ok${NC}    $1"; }
warn() { echo -e "  ${YELLOW}warn${NC}  $1"; }
fail() { echo -e "  ${RED}FAIL${NC}  $1"; exit 1; }

atomic_install() {
    local mode="$1" src="$2" dst="$3" owner="${4:-}" group="${5:-}" tmp="${3}.new.$$"
    if [ -n "$owner" ]; then
        install -m "$mode" -o "$owner" -g "$group" "$src" "$tmp" || return 1
    else
        install -m "$mode" "$src" "$tmp" || return 1
    fi
    mv -f "$tmp" "$dst"
}

echo -e "${BOLD}=== Deploy laptop-exec (SSH-first) ===${NC}"
[ "$EUID" -eq 0 ] || fail "run as root: sudo claude-server deploy-laptop-exec"
SERVER_DIR="${SERVER_DIR:-/usr/local/lib/claude-server}"
mkdir -p "$SERVER_DIR/cursor-rules" "$SERVER_DIR/skills/laptop-exec" "$SERVER_DIR/cursor-hooks" "$SERVER_DIR/tests"
STAGE_USER="${LAPTOP_EXEC_STAGE_USER:-smart}"
CLIENT_BUNDLE="/usr/local/share/claude-client"
REPO_ROOT="/home/$STAGE_USER/mounts/claude-code-server"
LE_STAGE=$(mktemp -d /tmp/le-deploy-stage.XXXXXX)
trap 'rm -rf "$LE_STAGE"' EXIT

_strip_crlf() {
    local f="$1"
    [ -f "$f" ] || return 0
    # Windows MCP / zip / scp leave CR; bash then dies with $'\r': command not found.
    sed -i 's/\r$//' "$f" 2>/dev/null || true
    if grep -q $'\r' "$f" 2>/dev/null; then
        tr -d '\r' < "$f" > "${f}.nocr" && mv -f "${f}.nocr" "$f"
    fi
}

_same_path() {
    local a b
    a=$(readlink -f "$1" 2>/dev/null || printf '%s' "$1")
    b=$(readlink -f "$2" 2>/dev/null || printf '%s' "$2")
    [ -n "$a" ] && [ "$a" = "$b" ]
}

# Pull scripts/server/REL from laptop SoT into LE_STAGE (LF-stripped).
_stage_from_laptop() {
    local rel="$1"
    local out="$LE_STAGE/$rel"
    mkdir -p "$(dirname "$out")"
    command -v laptop-exec >/dev/null 2>&1 || return 1
    if ! sudo -u "$STAGE_USER" laptop-exec status >/dev/null 2>&1; then
        return 1
    fi
    if sudo -u "$STAGE_USER" laptop-exec read -p claude-code-server "scripts/server/$rel" > "$out" 2>/dev/null \
        && [ -s "$out" ]; then
        _strip_crlf "$out"
        return 0
    fi
    rm -f "$out"
    return 1
}

_marker_ok() {
    local f="$1" rel="$2"
    [ -f "$f" ] || return 1
    case "$rel" in
        laptop-exec.sh)
            grep -q '_read_next' "$f" && grep -q 'ControlPersist' "$f" && grep -q 'GIT_MODE="off"' "$f"
            ;;
        cursor-hooks/laptop-exec-session.sh)
            grep -q 'HEALTHY MOUNT' "$f"
            ;;
        skills/laptop-exec/SKILL.md)
            grep -q 'HARD RULE' "$f"
            ;;
        cursor-rules/laptop-exec.mdc)
            grep -q 'Healthy mount' "$f" || grep -q 'HARD:' "$f"
            ;;
        cursor-hooks/laptop-exec-guard.sh)
            grep -q 'HEALTHY MOUNT' "$f"
            ;;
        *)
            [ -s "$f" ]
            ;;
    esac
}

# Install first usable source into SERVER_DIR/dst_rel.
# Order: laptop-exec stage → explicit srcs… (caller puts REPO then BUNDLE).
_sync_golden_file() {
    local dst_rel="$1"; shift
    local dst="$SERVER_DIR/$dst_rel"
    local mode="${1:-644}"; shift
    local found="" src staged=""
    local -a srcs=()
    mkdir -p "$(dirname "$dst")"

    if _stage_from_laptop "$dst_rel"; then
        staged="$LE_STAGE/$dst_rel"
        if ! _marker_ok "$staged" "$dst_rel"; then
            case "$dst_rel" in
                laptop-exec.sh|cursor-hooks/*|skills/*|cursor-rules/*)
                    warn "$dst_rel: laptop stage missing expected markers — will try fallbacks"
                    staged=""
                    ;;
            esac
        fi
    fi

    srcs=()
    [ -n "$staged" ] && srcs+=("$staged")
    srcs+=("$@")
    for src in "${srcs[@]}"; do
        [ -n "$src" ] || continue
        [ -f "$src" ] || continue
        _same_path "$src" "$dst" && continue
        _strip_crlf "$src"
        if ! atomic_install "$mode" "$src" "$dst"; then
            warn "$dst_rel: install failed from $src"
            continue
        fi
        _strip_crlf "$dst"
        ok "$dst_rel <- $src"
        found=1
        break
    done
    [ -n "$found" ] || warn "$dst_rel: no staged source (keeping existing)"
}

_dst_is_fresh() {
    local dst="$1" rel="$2"
    _marker_ok "$dst" "$rel"
}

_sync_from_laptop() {
    local rel="$1"
    local mode="${2:-644}"
    local dst="$SERVER_DIR/$rel"
    _dst_is_fresh "$dst" "$rel" && return 0
    if _stage_from_laptop "$rel"; then
        if ! atomic_install "$mode" "$LE_STAGE/$rel" "$dst"; then
            return 1
        fi
        _strip_crlf "$dst"
        ok "$rel <- laptop repo (tunnel, refresh)"
        return 0
    fi
    return 1
}

echo -e "${BOLD}Sync golden bundle${NC}"
# laptop-exec stage is attempted inside _sync_golden_file first; then REPO mount,
# then CLIENT_BUNDLE (last — often stale).
_sync_golden_file "laptop-exec.sh" 755 \
    "$REPO_ROOT/scripts/server/laptop-exec.sh" \
    "$CLIENT_BUNDLE/server/laptop-exec.sh"
_sync_golden_file "claude-mount.sh" 755 \
    "$REPO_ROOT/scripts/server/claude-mount.sh" \
    "$CLIENT_BUNDLE/server/claude-mount.sh" \
    "$CLIENT_BUNDLE/mac/claude-mount.sh"
_sync_golden_file "claude-git-setup.sh" 755 \
    "$REPO_ROOT/scripts/server/claude-git-setup.sh" \
    "$CLIENT_BUNDLE/server/claude-git-setup.sh"
_sync_golden_file "laptop-exec-setup.sh" 755 \
    "$REPO_ROOT/scripts/server/laptop-exec-setup.sh" \
    "$CLIENT_BUNDLE/server/laptop-exec-setup.sh"
_sync_golden_file "cursor-rules/laptop-exec.mdc" 644 \
    "$REPO_ROOT/scripts/server/cursor-rules/laptop-exec.mdc" \
    "$CLIENT_BUNDLE/server/cursor-rules/laptop-exec.mdc"
_sync_golden_file "skills/laptop-exec/SKILL.md" 644 \
    "$REPO_ROOT/scripts/server/skills/laptop-exec/SKILL.md" \
    "$CLIENT_BUNDLE/server/skills/laptop-exec/SKILL.md"
_sync_golden_file "skills/laptop-exec/reference-windows-mcp.md" 644 \
    "$REPO_ROOT/scripts/server/skills/laptop-exec/reference-windows-mcp.md" \
    "$CLIENT_BUNDLE/server/skills/laptop-exec/reference-windows-mcp.md"
for _hf in laptop-exec-audit-log.sh laptop-exec-guard.sh laptop-exec-guard-wrap.sh laptop-exec-shell-scan.py laptop-exec-session.sh; do
  _mode=755
  [[ "$_hf" == *.py ]] && _mode=644
  _sync_golden_file "cursor-hooks/$_hf" "$_mode" \
      "$REPO_ROOT/scripts/server/cursor-hooks/$_hf" \
      "$CLIENT_BUNDLE/server/cursor-hooks/$_hf"
done
_sync_golden_file "tests/test-laptop-exec.sh" 755 \
    "$REPO_ROOT/scripts/server/tests/test-laptop-exec.sh" \
    "$CLIENT_BUNDLE/server/tests/test-laptop-exec.sh"

# Refresh anything still missing markers from laptop SoT.
_sync_from_laptop "laptop-exec.sh" 755 || true
_sync_from_laptop "claude-mount.sh" 755 || true
_sync_from_laptop "cursor-rules/laptop-exec.mdc" 644 || true
_sync_from_laptop "skills/laptop-exec/SKILL.md" 644 || true
_sync_from_laptop "cursor-hooks/laptop-exec-session.sh" 755 || true
_sync_from_laptop "cursor-hooks/laptop-exec-guard.sh" 755 || true
_sync_from_laptop "tests/test-laptop-exec.sh" 755 || true

[ -f "$SERVER_DIR/laptop-exec.sh" ] || fail "missing $SERVER_DIR/laptop-exec.sh"
grep -q 'GIT_MODE="off"' "$SERVER_DIR/laptop-exec.sh" || fail "laptop-exec.sh missing GIT_MODE=off (run deploy-client-bundle first?)"
grep -q 'ControlPersist' "$SERVER_DIR/laptop-exec.sh" || warn "laptop-exec.sh may be outdated (no ControlPersist)"
grep -q '_read_next' "$SERVER_DIR/laptop-exec.sh" || fail "laptop-exec.sh missing _read_next (UX DIE helpers) — laptop SoT not synced"
[ -f "$SERVER_DIR/claude-mount.sh" ] || fail "missing $SERVER_DIR/claude-mount.sh"
grep -q 'GIT_MODE="off"' "$SERVER_DIR/claude-mount.sh" || fail "claude-mount.sh missing GIT_MODE=off"
grep -q 'HEALTHY MOUNT' "$SERVER_DIR/cursor-hooks/laptop-exec-session.sh" 2>/dev/null \
    || fail "session hook missing HEALTHY MOUNT paste — refuse to ship stale hooks"
grep -q 'HARD RULE' "$SERVER_DIR/skills/laptop-exec/SKILL.md" 2>/dev/null \
    || fail "SKILL.md missing HARD RULE — refuse to ship stale skill"
grep -q 'HEALTHY MOUNT' "$SERVER_DIR/cursor-hooks/laptop-exec-guard.sh" 2>/dev/null \
    || fail "guard missing HEALTHY MOUNT Task paste — refuse to ship stale guard"
# No CR left in shipped shells
for _f in "$SERVER_DIR/laptop-exec.sh" \
          "$SERVER_DIR/cursor-hooks/laptop-exec-session.sh" \
          "$SERVER_DIR/cursor-hooks/laptop-exec-guard.sh" \
          "$SERVER_DIR/cursor-hooks/laptop-exec-guard-wrap.sh"; do
  [ -f "$_f" ] || continue
  _strip_crlf "$_f"
  if grep -q $'\r' "$_f" 2>/dev/null; then
    fail "CRLF still present in $_f after strip"
  fi
done
ok "marker + LF verify"

# Keep BOTH install layouts in sync (flat = legacy; commands/ = preferred by claude-server).
# Agents previously updated only commands/ while claude-server ran the stale flat copy.
if _stage_from_laptop "commands/deploy-laptop-exec.sh"; then
  _strip_crlf "$LE_STAGE/commands/deploy-laptop-exec.sh"
  atomic_install 755 "$LE_STAGE/commands/deploy-laptop-exec.sh" "$SERVER_DIR/deploy-laptop-exec.sh" || true
  mkdir -p "$SERVER_DIR/commands"
  atomic_install 755 "$LE_STAGE/commands/deploy-laptop-exec.sh" "$SERVER_DIR/commands/deploy-laptop-exec.sh" || true
  ok "deploy-laptop-exec.sh -> flat + commands/ (self)"
fi

_strip_crlf "$SERVER_DIR/laptop-exec.sh"
atomic_install 755 "$SERVER_DIR/laptop-exec.sh" /usr/local/bin/laptop-exec
ok "laptop-exec -> /usr/local/bin/"
if [ -f "$SERVER_DIR/claude-mount.sh" ]; then
    _strip_crlf "$SERVER_DIR/claude-mount.sh"
    atomic_install 755 "$SERVER_DIR/claude-mount.sh" /usr/local/lib/claude-mount
    ln -sf /usr/local/lib/claude-mount /usr/local/bin/claude-mount 2>/dev/null || true
    ok "claude-mount -> /usr/local/lib/claude-mount"
fi
[ -f "$SERVER_DIR/claude-git-setup.sh" ] && _strip_crlf "$SERVER_DIR/claude-git-setup.sh" \
    && atomic_install 755 "$SERVER_DIR/claude-git-setup.sh" /usr/local/lib/claude-git-setup && ok "claude-git-setup -> /usr/local/lib/"

for f in cursor-rules/laptop-exec.mdc skills/laptop-exec/SKILL.md skills/laptop-exec/reference-windows-mcp.md \
         cursor-hooks/laptop-exec-audit-log.sh cursor-hooks/laptop-exec-guard.sh cursor-hooks/laptop-exec-guard-wrap.sh \
         cursor-hooks/laptop-exec-shell-scan.py cursor-hooks/laptop-exec-session.sh \
         cursor-hooks/hooks-user.json cursor-hooks/hooks-project.json; do
  [ -f "$SERVER_DIR/$f" ] || continue
  dst="/usr/local/lib/claude-server/$f"
  src="$SERVER_DIR/$f"
  _strip_crlf "$src"
  if _same_path "$src" "$dst"; then
    ok "$f (in place)"
    continue
  fi
  mkdir -p "/usr/local/lib/claude-server/$(dirname "$f")"
  if [[ "$f" == *.sh || "$f" == *.py ]]; then
    install -m 755 "$src" "$dst"
  else
    install -m 644 "$src" "$dst"
  fi
  ok "$f"
done
[ -f "$SERVER_DIR/laptop-exec-setup.sh" ] && _strip_crlf "$SERVER_DIR/laptop-exec-setup.sh" \
    && atomic_install 755 "$SERVER_DIR/laptop-exec-setup.sh" /usr/local/bin/laptop-exec-setup && ok "laptop-exec-setup"
if [ -f "$SERVER_DIR/claude-self-heal.sh" ]; then
    _strip_crlf "$SERVER_DIR/claude-self-heal.sh"
    atomic_install 755 "$SERVER_DIR/claude-self-heal.sh" /usr/local/bin/claude-self-heal && ok "claude-self-heal"
fi
if [ -f "$SERVER_DIR/tests/test-laptop-exec.sh" ]; then
    dst="/usr/local/lib/claude-server/tests/test-laptop-exec.sh"
    _strip_crlf "$SERVER_DIR/tests/test-laptop-exec.sh"
    if _same_path "$SERVER_DIR/tests/test-laptop-exec.sh" "$dst"; then
        ok "tests/test-laptop-exec.sh (in place)"
    else
        install -m 755 "$SERVER_DIR/tests/test-laptop-exec.sh" "$dst"
        ok "tests/test-laptop-exec.sh"
    fi
fi

echo -e "${BOLD}Deploy to users${NC}"
getent passwd | awk -F: '$3 >= 1000 && $1 != "nobody" && $1 != "nfsnobody" { print $1 ":" $6 }' | while IFS=: read -r u h; do
  [ -n "$u" ] && [ -n "$h" ] && [ -d "$h" ] || continue
  install -d -m 755 -o "$u" -g "$u" "$h/.local/bin" "$h/.cursor/rules" "$h/.cursor/skills/laptop-exec" "$h/.cursor/hooks"
  atomic_install 755 /usr/local/bin/laptop-exec "$h/.local/bin/laptop-exec" "$u" "$u"
  [ -f /usr/local/bin/laptop-exec-setup ] && atomic_install 755 /usr/local/bin/laptop-exec-setup "$h/.local/bin/laptop-exec-setup" "$u" "$u" && _strip_crlf "$h/.local/bin/laptop-exec-setup" || true
  [ -f /usr/local/bin/claude-automount ] && atomic_install 755 /usr/local/bin/claude-automount "$h/.local/bin/claude-automount" "$u" "$u" && _strip_crlf "$h/.local/bin/claude-automount" || true
  [ -f /usr/local/bin/claude-self-heal ] && atomic_install 755 /usr/local/bin/claude-self-heal "$h/.local/bin/claude-self-heal" "$u" "$u" && _strip_crlf "$h/.local/bin/claude-self-heal" || true
  _strip_crlf "$h/.local/bin/laptop-exec"
  [ -f "$SERVER_DIR/claude-mount.sh" ] && atomic_install 755 "$SERVER_DIR/claude-mount.sh" "$h/.local/bin/claude-mount" "$u" "$u"
  [ -f "$SERVER_DIR/claude-git-setup.sh" ] && atomic_install 755 "$SERVER_DIR/claude-git-setup.sh" "$h/.local/bin/claude-git-setup" "$u" "$u"
  install -m 644 -o "$u" -g "$u" "$SERVER_DIR/cursor-rules/laptop-exec.mdc" "$h/.cursor/rules/laptop-exec.mdc"
  install -m 644 -o "$u" -g "$u" "$SERVER_DIR/skills/laptop-exec/SKILL.md" "$h/.cursor/skills/laptop-exec/SKILL.md"
  [ -f "$SERVER_DIR/skills/laptop-exec/reference-windows-mcp.md" ] && \
    install -m 644 -o "$u" -g "$u" "$SERVER_DIR/skills/laptop-exec/reference-windows-mcp.md" \
      "$h/.cursor/skills/laptop-exec/reference-windows-mcp.md"
  for _hf in laptop-exec-audit-log.sh laptop-exec-guard.sh laptop-exec-guard-wrap.sh laptop-exec-shell-scan.py laptop-exec-session.sh; do
    [ -f "$SERVER_DIR/cursor-hooks/$_hf" ] || continue
    install -m 755 -o "$u" -g "$u" "$SERVER_DIR/cursor-hooks/$_hf" "$h/.cursor/hooks/$_hf"
    _strip_crlf "$h/.cursor/hooks/$_hf"
  done
  # Refuse to leave a user with broken session (bash -n)
  if ! bash -n "$h/.cursor/hooks/laptop-exec-session.sh" 2>/dev/null; then
    fail "user $u: session hook fails bash -n (CRLF/syntax) — abort"
  fi
  sudo -u "$u" /usr/local/bin/laptop-exec-setup --user 2>/dev/null || true
  sudo -u "$u" /usr/local/bin/laptop-exec-setup --all-projects 2>/dev/null || true
  ok "user $u"
done
echo -e "${GREEN}Done.${NC} Verify: laptop-exec test && sudo claude-server verify"
