#!/usr/bin/env bash
# _live-fleet-cmd-flash-audit.sh - DEEP LIVE fleet audit for Windows CMD flash fix
set -u
fail=0
check() {
    if eval "$2"; then
        echo "LIVE_PASS $1"
    else
        echo "LIVE_FAIL $1"
        fail=1
    fi
}

bin_h=$(sha256sum /usr/local/bin/claude-mount | awk '{print $1}')
lib_h=$(sha256sum /usr/local/lib/claude-mount | awk '{print $1}')
check bin_lib_same "[ \"$bin_h\" = \"$lib_h\" ]"
check bin_is_symlink "[ -L /usr/local/bin/claude-mount ]"
check global_push_hidden "grep -q ssh_l_ps_hidden /usr/local/bin/claude-client-push-laptop"
check global_push_idle "grep -q CLAUDE_CLIENT_PUSH_IDLE_SECS:-900 /usr/local/bin/claude-client-push-laptop"
check global_push_no_cmd "! grep -q 'cmd /c if exist' /usr/local/bin/claude-client-push-laptop"
check global_mount_no_cmd "! grep -q 'cmd /c exit 0' /usr/local/bin/claude-mount /usr/local/lib/claude-mount"
check global_mount_hidden "grep -q 'WindowStyle Hidden -Command exit' /usr/local/bin/claude-mount"
check live_mount_no_attrib "! grep -qE 'cmd /c .attrib' /usr/local/lib/claude-mount"
check global_heal_no_cmd "! grep -q 'cmd /c exit 0' /usr/local/bin/claude-self-heal"
check global_le_no_cmd "! grep -q 'cmd /c exit 0' /usr/local/bin/laptop-exec"
check global_le_no_cmd_any "! grep -vE '^[[:space:]]*#' /usr/local/bin/laptop-exec | grep -q 'cmd /c'"
# Version must be self-consistent (txt == ConnectVersion in connect.ps1), not a hard-coded stamp.
BUNDLE_VER="$(tr -d '\r\n' </usr/local/share/claude-client/connect-version.txt)"
check bundle_ver "printf '%s' \"$BUNDLE_VER\" | grep -Eq '^[0-9]{8}\\.[0-9]+$' && grep -Fq \"ConnectVersion = '$BUNDLE_VER'\" /usr/local/share/claude-client/connect.ps1"
check bundle_git_clean "! grep -q 'cmd /c exit 0' /usr/local/share/claude-client/git-mode.ps1"

check src_mount_no_cmd "! grep -q 'cmd /c exit 0' /usr/local/lib/claude-server/claude-mount.sh"
check src_mount_no_attrib "! grep -qE 'cmd /c .attrib' /usr/local/lib/claude-server/claude-mount.sh"
check src_mount_hidden "grep -q 'WindowStyle Hidden -Command exit' /usr/local/lib/claude-server/claude-mount.sh"
check src_le_no_cmd "! grep -q 'cmd /c exit 0' /usr/local/lib/claude-server/laptop-exec.sh"
check src_le_hidden "grep -q 'WindowStyle Hidden -Command exit' /usr/local/lib/claude-server/laptop-exec.sh"
bh=$(sha256sum /usr/local/bin/claude-git-setup | awk '{print $1}')
lh=$(sha256sum /usr/local/lib/claude-git-setup | awk '{print $1}')
check git_setup_sync "[ \"$bh\" = \"$lh\" ]"

GOLD="$bin_h"
users=0; dirty=0; miss=0; mismatch=0
for h in /home/*; do
    [ -d "$h" ] || continue
    u=$(basename "$h")
    id "$u" >/dev/null 2>&1 || continue
    case "$u" in root|lost+found|administrator) continue ;; esac
    users=$((users + 1))
    for b in claude-mount claude-self-heal laptop-exec; do
        p="$h/.local/bin/$b"
        if [ ! -x "$p" ]; then
            echo "LIVE_FAIL user_miss_${u}_${b}"
            miss=$((miss + 1)); fail=1; continue
        fi
        if grep -q 'cmd /c exit 0' "$p" 2>/dev/null; then
            echo "LIVE_FAIL user_dirty_${u}_${b}"
            dirty=$((dirty + 1)); fail=1
        fi
        if ! grep -q 'WindowStyle Hidden' "$p" 2>/dev/null; then
            echo "LIVE_FAIL user_nohidden_${u}_${b}"
            fail=1
        fi
    done
    mh=$(sha256sum "$h/.local/bin/claude-mount" | awk '{print $1}')
    if [ "$mh" != "$GOLD" ]; then
        echo "LIVE_FAIL user_hash_${u}"
        mismatch=$((mismatch + 1)); fail=1
    else
        echo "LIVE_PASS user_ok_${u}"
    fi
done

echo "LIVE_PASS fleet_users_${users}"
check fleet_min_users "[ $users -ge 8 ]"
check fleet_no_miss "[ $miss -eq 0 ]"
check fleet_no_dirty "[ $dirty -eq 0 ]"
check fleet_no_mismatch "[ $mismatch -eq 0 ]"

u=smart
stamp="/home/$u/.cache/claude-client-push.stamp"
mkdir -p "/home/$u/.cache"
date +%s > "$stamp"
chown "$u:$u" "$stamp" 2>/dev/null || true
start=$(date +%s)
sudo -u "$u" -H env FORCE=0 /usr/local/bin/claude-client-push-laptop >/dev/null 2>&1 || true
end=$(date +%s)
dur=$((end - start))
check push_idle_fast "[ $dur -le 2 ]"

exit "$fail"
