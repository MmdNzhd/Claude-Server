# cursor-proxy-sidecar.sh - sticky front door 18999/18998 -> 19080/19180
CURSOR_SOCKS_FRONT_PORT="${CURSOR_SOCKS_FRONT_PORT:-18999}"
CURSOR_HTTP_FRONT_PORT="${CURSOR_HTTP_FRONT_PORT:-18998}"
export CURSOR_SOCKS_FRONT_PORT CURSOR_HTTP_FRONT_PORT

start_cursor_proxy_sidecar() {
    local socks_back="${SOCKS_PROXY_PORT:-19080}"
    local http_back="${HTTP_PROXY_PORT:-19180}"
    local front_s="$CURSOR_SOCKS_FRONT_PORT"
    local front_h="$CURSOR_HTTP_FRONT_PORT"
    local pidfile="${TMPDIR:-/tmp}/claude-connect-sidecar.pids"
    # Prefer socat if present; else python3 relay
    _sidecar_one() {
        local listen="$1" back="$2" name="$3"
        if command -v nc >/dev/null 2>&1; then
            if nc -z 127.0.0.1 "$listen" 2>/dev/null; then
                declare -F connect_log >/dev/null 2>&1 && connect_log "SIDECAR_START name=$name listen=$listen backend=$back ok=1 reused=1" 'INFO'
                return 0
            fi
        fi
        if command -v socat >/dev/null 2>&1; then
            socat TCP-LISTEN:"$listen",bind=127.0.0.1,reuseaddr,fork TCP:127.0.0.1:"$back" >/dev/null 2>&1 &
            echo $! >>"$pidfile"
            declare -F connect_log >/dev/null 2>&1 && connect_log "SIDECAR_START name=$name listen=$listen backend=$back ok=1 via=socat" 'INFO'
            return 0
        fi
        python3 - "$listen" "$back" <<'PY' >/dev/null 2>&1 &
import socket, threading, sys
listen, back = int(sys.argv[1]), int(sys.argv[2])
srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", listen))
srv.listen(64)

def pipe(a, b):
    try:
        while True:
            d = a.recv(16384)
            if not d: break
            b.sendall(d)
    except Exception:
        pass
    finally:
        try: a.close()
        except Exception: pass
        try: b.close()
        except Exception: pass

while True:
    c, _ = srv.accept()
    try:
        r = socket.create_connection(("127.0.0.1", back), timeout=5)
    except Exception:
        c.close()
        continue
    threading.Thread(target=pipe, args=(c, r), daemon=True).start()
    threading.Thread(target=pipe, args=(r, c), daemon=True).start()
PY
        echo $! >>"$pidfile"
        declare -F connect_log >/dev/null 2>&1 && connect_log "SIDECAR_START name=$name listen=$listen backend=$back ok=1 via=python" 'INFO'
        return 0
    }
    _sidecar_one "$front_s" "$socks_back" socks
    _sidecar_one "$front_h" "$http_back" http
    return 0
}
# Boot-once heal: sticky fronts up with dead -L backends blackhole Cursor chat (Win Ensure parity).
heal_cursor_proxy_sidecar_blackhole() {
    local front_h="${CURSOR_HTTP_FRONT_PORT:-18998}"
    local front_s="${CURSOR_SOCKS_FRONT_PORT:-18999}"
    local http_back="${HTTP_PROXY_PORT:-19180}"
    local socks_back="${SOCKS_PROXY_PORT:-19080}"
    local pidfile="${TMPDIR:-/tmp}/claude-connect-sidecar.pids"
    local front_up=0 backend_up=0
    if command -v nc >/dev/null 2>&1; then
        if nc -z 127.0.0.1 "$front_h" 2>/dev/null || nc -z 127.0.0.1 "$front_s" 2>/dev/null; then
            front_up=1
        fi
        if nc -z 127.0.0.1 "$http_back" 2>/dev/null || nc -z 127.0.0.1 "$socks_back" 2>/dev/null; then
            backend_up=1
        fi
    fi
    if [ "$front_up" -eq 1 ] && [ "$backend_up" -eq 0 ]; then
        declare -F connect_log >/dev/null 2>&1 && \
            connect_log "SIDECAR_HEAL_BLACKHOLE front_up backend_down" 'WARN'
        if [ -f "$pidfile" ]; then
            while IFS= read -r pid || [ -n "$pid" ]; do
                [ -n "$pid" ] || continue
                kill "$pid" 2>/dev/null || true
            done <"$pidfile"
            rm -f "$pidfile" 2>/dev/null || true
        fi
        # Best-effort: drop any leftover listeners on sticky fronts.
        if command -v lsof >/dev/null 2>&1; then
            for p in "$front_h" "$front_s"; do
                lsof -tiTCP:"$p" -sTCP:LISTEN 2>/dev/null | while read -r pid; do
                    kill "$pid" 2>/dev/null || true
                done
            done
        fi
        if declare -F clear_cursor_proxy_settings >/dev/null 2>&1; then
            clear_cursor_proxy_settings || true
        fi
        return 0
    fi
    return 0
}
