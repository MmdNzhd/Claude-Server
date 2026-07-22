#!/bin/bash
# deploy-laptop-exec.sh - redeploy SSH-first laptop-exec to server + all users
set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
ok() { echo -e "  ${GREEN}ok${NC}    $1"; }
warn() { echo -e "  ${YELLOW}warn${NC}  $1"; }
fail() { echo -e "  ${RED}FAIL${NC}  $1"; exit 1; }

# atomic_install MODE SRC DST [OWNER] [GROUP]
# Installs SRC to DST via a same-directory temp file + rename so a process already
# executing DST (laptop-exec is invoked constantly; claude-watchdog polls
# claude-mount every 30s) never observes a partially-written file.
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

_sync_golden_file() {
    local dst_rel="$1"; shift
    local dst="$SERVER_DIR/$dst_rel"
    local mode="${1:-644}"; shift
    local found=""
    for src in "$@"; do
        [ -f "$src" ] || continue
        install -m "$mode" "$src" "$dst"
        ok "$dst_rel <- $src"
        found=1
        break
    done
    [ -n "$found" ] || warn "$dst_rel: no staged source (keeping existing)"
}

_dst_is_fresh() {
    local dst="$1" rel="$2"
    [ -f "$dst" ] || return 1
    case "$rel" in
        laptop-exec.sh) grep -q 'ControlPersist' "$dst" && grep -q 'GIT_MODE="off"' "$dst" ;;
        claude-mount.sh) grep -q 'GIT_MODE="off"' "$dst" ;;
        *) [ -s "$dst" ] ;;
    esac
}

_sync_from_laptop() {
    local rel="$1"
    local mode="${2:-644}"
    local dst="$SERVER_DIR/$rel"
    _dst_is_fresh "$dst" "$rel" && return 0
    command -v laptop-exec >/dev/null 2>&1 || return 0
    if sudo -u "$STAGE_USER" laptop-exec status >/dev/null 2>&1; then
        mkdir -p "$(dirname "$dst")"
        if sudo -u "$STAGE_USER" laptop-exec read -p claude-code-server "scripts/server/$rel" > "${dst}.tmp" 2>/dev/null; then
            [ -s "${dst}.tmp" ] || { rm -f "${dst}.tmp"; return 1; }
            install -m "$mode" "${dst}.tmp" "$dst"
            rm -f "${dst}.tmp"
            ok "$rel <- laptop repo (tunnel)"
            return 0
        fi
    fi
    return 1
}

CLIENT_BUNDLE="/usr/local/share/claude-client"
REPO_ROOT="/home/$STAGE_USER/mounts/claude-code-server"

echo -e "${BOLD}Sync golden bundle${NC}"
# Prefer client bundle / repo over per-user copies (user ~/.local/bin may be stale).
_sync_golden_file "laptop-exec.sh" 755 \
    "$CLIENT_BUNDLE/server/laptop-exec.sh" \
    "$REPO_ROOT/scripts/server/laptop-exec.sh" \
    "$SERVER_DIR/laptop-exec.sh" \
    "/home/$STAGE_USER/.local/bin/laptop-exec"
_sync_golden_file "claude-mount.sh" 755 \
    "$CLIENT_BUNDLE/server/claude-mount.sh" \
    "$CLIENT_BUNDLE/mac/claude-mount.sh" \
    "$REPO_ROOT/scripts/server/claude-mount.sh" \
    "$SERVER_DIR/claude-mount.sh"
_sync_golden_file "claude-git-setup.sh" 755 \
    "$CLIENT_BUNDLE/server/claude-git-setup.sh" \
    "$REPO_ROOT/scripts/server/claude-git-setup.sh" \
    "$SERVER_DIR/claude-git-setup.sh"
_sync_golden_file "laptop-exec-setup.sh" 755 \
    "$CLIENT_BUNDLE/server/laptop-exec-setup.sh" \
    "$REPO_ROOT/scripts/server/laptop-exec-setup.sh" \
    "$SERVER_DIR/laptop-exec-setup.sh"
_sync_golden_file "cursor-rules/laptop-exec.mdc" 644 \
    "$CLIENT_BUNDLE/server/cursor-rules/laptop-exec.mdc" \
    "$REPO_ROOT/scripts/server/cursor-rules/laptop-exec.mdc" \
    "/home/$STAGE_USER/.cursor/rules/laptop-exec.mdc" \
    "$SERVER_DIR/cursor-rules/laptop-exec.mdc"
_sync_golden_file "skills/laptop-exec/SKILL.md" 644 \
    "$CLIENT_BUNDLE/server/skills/laptop-exec/SKILL.md" \
    "$REPO_ROOT/scripts/server/skills/laptop-exec/SKILL.md" \
    "/home/$STAGE_USER/.cursor/skills/laptop-exec/SKILL.md" \
    "$SERVER_DIR/skills/laptop-exec/SKILL.md"

if ! grep -q 'GIT_MODE="off"' "$SERVER_DIR/laptop-exec.sh" 2>/dev/null; then
    _sync_from_laptop "laptop-exec.sh" 755 || true
fi
if ! grep -q 'GIT_MODE="off"' "$SERVER_DIR/claude-mount.sh" 2>/dev/null; then
    _sync_from_laptop "claude-mount.sh" 755 || true
fi
_sync_from_laptop "cursor-rules/laptop-exec.mdc" 644 || true
_sync_from_laptop "skills/laptop-exec/SKILL.md" 644 || true
_sync_from_laptop "tests/test-laptop-exec.sh" 755 || true

[ -f "$SERVER_DIR/laptop-exec.sh" ] || fail "missing $SERVER_DIR/laptop-exec.sh"
grep -q 'GIT_MODE="off"' "$SERVER_DIR/laptop-exec.sh" || fail "laptop-exec.sh missing GIT_MODE=off (run deploy-client-bundle first?)"
grep -q 'ControlPersist' "$SERVER_DIR/laptop-exec.sh" || warn "laptop-exec.sh may be outdated (no ControlPersist)"
[ -f "$SERVER_DIR/claude-mount.sh" ] || fail "missing $SERVER_DIR/claude-mount.sh"
grep -q 'GIT_MODE="off"' "$SERVER_DIR/claude-mount.sh" || fail "claude-mount.sh missing GIT_MODE=off"

# Windows zip/scp can leave CRLF and break bash ($'\r': command not found) - strip
# on the staged source before installing (install itself lands atomically below).
sed -i 's/\r$//' "$SERVER_DIR/laptop-exec.sh" 2>/dev/null || true
atomic_install 755 "$SERVER_DIR/laptop-exec.sh" /usr/local/bin/laptop-exec
ok "laptop-exec -> /usr/local/bin/"
if [ -f "$SERVER_DIR/claude-mount.sh" ]; then
    atomic_install 755 "$SERVER_DIR/claude-mount.sh" /usr/local/lib/claude-mount
    ln -sf /usr/local/lib/claude-mount /usr/local/bin/claude-mount 2>/dev/null || true
    ok "claude-mount -> /usr/local/lib/claude-mount"
fi
[ -f "$SERVER_DIR/claude-git-setup.sh" ] && atomic_install 755 "$SERVER_DIR/claude-git-setup.sh" /usr/local/lib/claude-git-setup && ok "claude-git-setup -> /usr/local/lib/"

for f in cursor-rules/laptop-exec.mdc skills/laptop-exec/SKILL.md cursor-hooks/laptop-exec-guard.sh cursor-hooks/laptop-exec-guard-wrap.sh cursor-hooks/laptop-exec-shell-scan.py cursor-hooks/laptop-exec-session.sh cursor-hooks/hooks-user.json cursor-hooks/hooks-project.json; do
  [ -f "$SERVER_DIR/$f" ] || continue
  dst="/usr/local/lib/claude-server/$f"
  src="$SERVER_DIR/$f"
  [ "$src" -ef "$dst" ] && ok "$f (in place)" && continue
  mkdir -p "/usr/local/lib/claude-server/$(dirname "$f")"
  install -m 644 "$src" "$dst" 2>/dev/null || install -m 755 "$src" "$dst"
  ok "$f"
done
[ -f "$SERVER_DIR/laptop-exec-setup.sh" ] && atomic_install 755 "$SERVER_DIR/laptop-exec-setup.sh" /usr/local/bin/laptop-exec-setup && ok "laptop-exec-setup"
if [ -f "$SERVER_DIR/claude-self-heal.sh" ]; then
    sed -i 's/\r$//' "$SERVER_DIR/claude-self-heal.sh" 2>/dev/null || true
    atomic_install 755 "$SERVER_DIR/claude-self-heal.sh" /usr/local/bin/claude-self-heal && ok "claude-self-heal"
fi
if [ -f "$SERVER_DIR/tests/test-laptop-exec.sh" ]; then
    dst="/usr/local/lib/claude-server/tests/test-laptop-exec.sh"
    if [ "$SERVER_DIR/tests/test-laptop-exec.sh" -ef "$dst" ]; then
        ok "tests/test-laptop-exec.sh (in place)"
    else
        install -m 755 "$SERVER_DIR/tests/test-laptop-exec.sh" "$dst"
        ok "tests/test-laptop-exec.sh"
    fi
fi

# All interactive human accounts (Smart + Sepidz + future users). Hardcoded lists miss Sepidz.
echo -e "${BOLD}Deploy to users${NC}"
getent passwd | awk -F: '$3 >= 1000 && $1 != "nobody" && $1 != "nfsnobody" { print $1 ":" $6 }' | while IFS=: read -r u h; do
  [ -n "$u" ] && [ -n "$h" ] && [ -d "$h" ] || continue
  install -d -m 755 -o "$u" -g "$u" "$h/.local/bin" "$h/.cursor/rules" "$h/.cursor/skills/laptop-exec" "$h/.cursor/hooks"
  atomic_install 755 /usr/local/bin/laptop-exec "$h/.local/bin/laptop-exec" "$u" "$u"
  [ -f /usr/local/bin/laptop-exec-setup ] && atomic_install 755 /usr/local/bin/laptop-exec-setup "$h/.local/bin/laptop-exec-setup" "$u" "$u" && sed -i 's/\r$//' "$h/.local/bin/laptop-exec-setup" 2>/dev/null || true
  [ -f /usr/local/bin/claude-automount ] && atomic_install 755 /usr/local/bin/claude-automount "$h/.local/bin/claude-automount" "$u" "$u" && sed -i 's/\r$//' "$h/.local/bin/claude-automount" 2>/dev/null || true
  [ -f /usr/local/bin/claude-self-heal ] && atomic_install 755 /usr/local/bin/claude-self-heal "$h/.local/bin/claude-self-heal" "$u" "$u" && sed -i 's/\r$//' "$h/.local/bin/claude-self-heal" 2>/dev/null || true
  sed -i 's/\r$//' "$h/.local/bin/laptop-exec" 2>/dev/null || true
  [ -f "$SERVER_DIR/claude-mount.sh" ] && atomic_install 755 "$SERVER_DIR/claude-mount.sh" "$h/.local/bin/claude-mount" "$u" "$u"
  [ -f "$SERVER_DIR/claude-git-setup.sh" ] && atomic_install 755 "$SERVER_DIR/claude-git-setup.sh" "$h/.local/bin/claude-git-setup" "$u" "$u"
  install -m 644 -o "$u" -g "$u" "$SERVER_DIR/cursor-rules/laptop-exec.mdc" "$h/.cursor/rules/laptop-exec.mdc"
  install -m 644 -o "$u" -g "$u" "$SERVER_DIR/skills/laptop-exec/SKILL.md" "$h/.cursor/skills/laptop-exec/SKILL.md"
  for _hf in laptop-exec-guard.sh laptop-exec-guard-wrap.sh laptop-exec-shell-scan.py laptop-exec-session.sh; do
    [ -f "$SERVER_DIR/cursor-hooks/$_hf" ] || continue
    install -m 755 -o "$u" -g "$u" "$SERVER_DIR/cursor-hooks/$_hf" "$h/.cursor/hooks/$_hf"
  done
  sudo -u "$u" /usr/local/bin/laptop-exec-setup --user 2>/dev/null || true
  sudo -u "$u" /usr/local/bin/laptop-exec-setup --all-projects 2>/dev/null || true
  ok "user $u"
done
echo -e "${GREEN}Done.${NC} Verify: laptop-exec test && sudo claude-server verify"



