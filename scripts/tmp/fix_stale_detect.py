from pathlib import Path
path = Path(r"D:\Smart\Claude-Code-Server\scripts\server\claude-self-heal.sh")
text = path.read_text(encoding="utf-8")
old = '''_heal_stale_mounts() {
    [ -d "$MOUNTS_DIR" ] || return 0
    if _tunnel_up; then
        return 0
    fi
    local d mp
    for d in "$MOUNTS_DIR"/*/; do
        [ -d "$d" ] || continue
        mp="${d%/}"
        if mountpoint -q "$mp" 2>/dev/null || grep -q " ${mp} " /proc/mounts 2>/dev/null; then
            _log "stale mount (tunnel down) → umount $mp"
            fusermount -uz "$mp" 2>/dev/null || umount -l "$mp" 2>/dev/null || true
        fi
    done
}
'''
new = '''_heal_stale_mounts() {
    [ -d "$MOUNTS_DIR" ] || return 0
    if _tunnel_up; then
        return 0
    fi
    local d mp
    # Never use mountpoint -q here: on frozen SSHFS it can hang indefinitely.
    # Detect only via /proc/mounts (instant).
    for d in "$MOUNTS_DIR"/*/; do
        [ -d "$d" ] || continue
        mp="${d%/}"
        if grep -F " $mp " /proc/mounts >/dev/null 2>&1; then
            _log "stale mount (tunnel down) -> umount $mp"
            # prefer fusermount as the mounting user; fall back to lazy umount
            timeout 5 fusermount -uz "$mp" 2>/dev/null \
              || timeout 5 umount -l "$mp" 2>/dev/null \
              || true
        fi
    done
}
'''
if old not in text:
    # try with arrow already broken encoding
    raise SystemExit('block not found exact')
path.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')
print('stale detect fixed')
