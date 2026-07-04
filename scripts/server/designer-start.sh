#!/bin/bash
# designer-start.sh - shared Claude Design session manager.
# Called via SSH from connect-design.ps1 as the "designer" user.
# Usage: designer-start [start W H | stop | status]
#
# Only one viewer at a time. A new connection kicks the previous one —
# the old client sees "Connection dropped" and gets a notification.

SUBCOMMAND="${1:-start}"
SCREEN_W="${2:-1920}"
SCREEN_H="${3:-1080}"

# Maximum framebuffer size — Xvfb is always started at this size;
# xrandr is used to switch to the requested resolution at runtime.
MAX_FB_W=3840
MAX_FB_H=2160

if ! [[ "$SCREEN_W" =~ ^[0-9]+$ ]] || ! [[ "$SCREEN_H" =~ ^[0-9]+$ ]]; then
    echo "ERROR: width and height must be positive integers (got: '$SCREEN_W' '$SCREEN_H')"
    exit 1
fi
if [ "$SCREEN_W" -lt 320 ] || [ "$SCREEN_W" -gt "$MAX_FB_W" ] || \
   [ "$SCREEN_H" -lt 240 ] || [ "$SCREEN_H" -gt "$MAX_FB_H" ]; then
    echo "ERROR: resolution ${SCREEN_W}x${SCREEN_H} is outside allowed range (320x240 – ${MAX_FB_W}x${MAX_FB_H})"
    exit 1
fi

UID_NUM=$(id -u)
if [ "$UID_NUM" -eq 0 ]; then
    DISPLAY_VAR=":99"
else
    DISPLAY_VAR=":${UID_NUM}"
fi

VNC_PORT=$((25000 + UID_NUM))
NOVNC_PORT=$((26000 + UID_NUM))

if [ "$VNC_PORT" -gt 65535 ] || [ "$NOVNC_PORT" -gt 65535 ]; then
    echo "ERROR: UID $UID_NUM is too large; computed port exceeds 65535."
    exit 1
fi

CHROME_PROFILE="/opt/chrome-design-profile"
SESSION_DIR="$HOME/.designer"
XVFB_PID="$SESSION_DIR/xvfb.pid"
WM_PID="$SESSION_DIR/wm.pid"
AUTOCUTSEL_PID="$SESSION_DIR/autocutsel.pid"
AUTOCUTSEL_PRI_PID="$SESSION_DIR/autocutsel_pri.pid"
VNC_PID="$SESSION_DIR/vnc.pid"
NOVNC_PID="$SESSION_DIR/novnc.pid"
CHROME_PID="$SESSION_DIR/chrome.pid"
KICKED_FILE="$SESSION_DIR/kicked"
RES_FILE="$SESSION_DIR/resolution"
LOG="$SESSION_DIR/session.log"

mkdir -p "$SESSION_DIR"

is_running() {
    local f="$1"
    local expected_name="${2:-}"
    [ -f "$f" ] || return 1
    local pid
    pid=$(cat "$f" 2>/dev/null) || return 1
    [ -n "$pid" ] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    if [ -n "$expected_name" ]; then
        local cmdline
        cmdline=$(cat "/proc/${pid}/cmdline" 2>/dev/null | tr '\0' ' ')
        echo "$cmdline" | grep -q "$expected_name" || return 1
    fi
    return 0
}

start_proc() {
    local pid_file="$1"; shift
    nohup setsid "$@" >> "$LOG" 2>&1 &
    echo $! > "$pid_file"
}

wait_for_xvfb() {
    local i=0
    local display_num="${DISPLAY_VAR#:}"
    local socket="/tmp/.X11-unix/X${display_num}"
    while [ ! -S "$socket" ]; do
        i=$((i + 1))
        [ $i -ge 30 ] && { echo "ERROR: Xvfb did not start in time (socket $socket missing)"; exit 1; }
        sleep 0.5
    done
}

wait_for_port() {
    local port="$1"
    local i=0
    while ! (ss -tlnp 2>/dev/null | grep -q ":${port}") && \
          ! (netstat -tlnp 2>/dev/null | grep -q ":${port}") && \
          ! (cat /proc/net/tcp /proc/net/tcp6 2>/dev/null | \
             awk '{print $2}' | grep -qi "$(printf '%04X' "$port")$"); do
        i=$((i + 1))
        [ $i -ge 40 ] && { echo "ERROR: port $port not ready after 20s"; exit 1; }
        sleep 0.5
    done
}

# Stop infrastructure services (Xvfb, x11vnc, websockify) — Chrome is NEVER touched here.
stop_services() {
    for pid_file in "$NOVNC_PID" "$VNC_PID" "$WM_PID" "$AUTOCUTSEL_PID" "$AUTOCUTSEL_PRI_PID" "$XVFB_PID"; do
        if [ -f "$pid_file" ]; then
            local _pid
            _pid=$(cat "$pid_file" 2>/dev/null)
            if [ -n "$_pid" ]; then
                kill "$_pid" 2>/dev/null || true
                local i=0
                while kill -0 "$_pid" 2>/dev/null && [ $i -lt 50 ]; do
                    sleep 0.1; i=$((i + 1))
                done
                kill -9 "$_pid" 2>/dev/null || true
            fi
            rm -f "$pid_file"
        fi
    done
    pkill -f "Xvfb ${DISPLAY_VAR}" 2>/dev/null || true
    pkill -f "x11vnc.*rfbport ${VNC_PORT}" 2>/dev/null || true
    pkill -f "websockify.*${NOVNC_PORT}" 2>/dev/null || true
    pkill -f "fluxbox.*-display ${DISPLAY_VAR}" 2>/dev/null || true
    pkill -f "autocutsel" 2>/dev/null || true
    sleep 1
}

# Stop Chrome — called ONLY from the explicit 'stop' subcommand or Xvfb restart.
stop_chrome() {
    if [ -f "$CHROME_PID" ]; then
        local _pid
        _pid=$(cat "$CHROME_PID" 2>/dev/null)
        if [ -n "$_pid" ]; then
            local pgid
            pgid=$(ps -o pgid= -p "$_pid" 2>/dev/null | tr -d ' ')
            if [ -n "$pgid" ] && [ "$pgid" != "0" ]; then
                kill -- "-${pgid}" 2>/dev/null || kill "$_pid" 2>/dev/null || true
            else
                kill "$_pid" 2>/dev/null || true
            fi
            local i=0
            while kill -0 "$_pid" 2>/dev/null && [ $i -lt 50 ]; do
                sleep 0.1; i=$((i + 1))
            done
            kill -9 "$_pid" 2>/dev/null || true
        fi
        rm -f "$CHROME_PID"
    fi
    pkill -f "chrome.*${CHROME_PROFILE}" 2>/dev/null || true
}

kick_viewer() {
    # Write KICKED_FILE FIRST, before killing websockify, so the client
    # sees it even on a fast reconnect before the kill completes.
    PREV_CLIENT=$(cat "$SESSION_DIR/client_id" 2>/dev/null)
    CURR_CLIENT="${SSH_CLIENT:-unknown}"
    if [ "$PREV_CLIENT" != "$CURR_CLIENT" ]; then
        touch "$KICKED_FILE"
    fi

    if [ -f "$NOVNC_PID" ]; then
        local _pid
        _pid=$(cat "$NOVNC_PID" 2>/dev/null)
        [ -n "$_pid" ] && kill "$_pid" 2>/dev/null || true
        rm -f "$NOVNC_PID"
    fi
    pkill -f "websockify.*${NOVNC_PORT}" 2>/dev/null || true
    # Wait until websockify is confirmed dead
    local i=0
    while pkill -0 -f "websockify.*${NOVNC_PORT}" 2>/dev/null && [ $i -lt 20 ]; do
        sleep 0.1; i=$((i + 1))
    done
}

apply_resolution() {
    local w="$1" h="$2"
    if ! command -v xrandr >/dev/null 2>&1; then
        return 1
    fi
    local modename="${w}x${h}"
    # Add mode if not already present
    if ! DISPLAY="$DISPLAY_VAR" xrandr 2>/dev/null | grep -q "^   ${modename}"; then
        if command -v cvt >/dev/null 2>&1; then
            local modeline
            modeline=$(cvt "$w" "$h" 60 2>/dev/null | grep Modeline | sed 's/Modeline //')
            if [ -n "$modeline" ]; then
                local modeargs
                modeargs=$(echo "$modeline" | sed 's/^"[^"]*" //')
                DISPLAY="$DISPLAY_VAR" xrandr --newmode "$modename" $modeargs 2>/dev/null || true
                local output
                output=$(DISPLAY="$DISPLAY_VAR" xrandr 2>/dev/null | grep ' connected' | awk '{print $1}' | head -1)
                [ -n "$output" ] && DISPLAY="$DISPLAY_VAR" xrandr --addmode "$output" "$modename" 2>/dev/null || true
            fi
        fi
    fi
    # Try --fb for simple framebuffer resize (works on Xvfb virtual outputs)
    DISPLAY="$DISPLAY_VAR" xrandr --fb "${w}x${h}" 2>/dev/null && return 0
    # Try switching mode on the connected output
    local output
    output=$(DISPLAY="$DISPLAY_VAR" xrandr 2>/dev/null | grep ' connected' | awk '{print $1}' | head -1)
    if [ -n "$output" ]; then
        DISPLAY="$DISPLAY_VAR" xrandr --output "$output" --mode "$modename" 2>/dev/null && return 0
    fi
    return 1
}

case "$SUBCOMMAND" in
    start)
        # Rotate log — keep last 500KB
        if [ -f "$LOG" ] && [ "$(wc -c < "$LOG" 2>/dev/null || echo 0)" -gt 512000 ]; then
            tail -c 512000 "$LOG" > "${LOG}.tmp" && [ -s "${LOG}.tmp" ] && mv "${LOG}.tmp" "$LOG" || rm -f "${LOG}.tmp"
        fi

        # If websockify is running, someone is already connected — kick them.
        if is_running "$NOVNC_PID" "websockify"; then
            kick_viewer
            echo "KICKED_PREVIOUS"
        fi

        # Record current client identity for future kick detection
        echo "${SSH_CLIENT:-unknown}" > "$SESSION_DIR/client_id"

        # Handle resolution change without restarting Xvfb or Chrome.
        STORED_RES=""
        [ -f "$RES_FILE" ] && STORED_RES=$(cat "$RES_FILE" 2>/dev/null)
        WANT_RES="${SCREEN_W}x${SCREEN_H}"

        if [ -n "$STORED_RES" ] && [ "$STORED_RES" != "$WANT_RES" ] && is_running "$XVFB_PID" "Xvfb"; then
            # Attempt live resolution change via xrandr — Chrome stays running.
            if apply_resolution "$SCREEN_W" "$SCREEN_H"; then
                echo "$WANT_RES" > "$RES_FILE"
                # Restart only x11vnc so it picks up the new geometry.
                if [ -f "$VNC_PID" ]; then
                    _pid=$(cat "$VNC_PID" 2>/dev/null)
                    [ -n "$_pid" ] && kill "$_pid" 2>/dev/null || true
                    rm -f "$VNC_PID"
                fi
                pkill -f "x11vnc.*rfbport ${VNC_PORT}" 2>/dev/null || true
                sleep 1
            else
                # xrandr failed — restart everything including Chrome
                # because Chrome cannot survive its display being destroyed.
                stop_chrome
                stop_services
            fi
        fi

        # If Xvfb crashed, tear down infrastructure and Chrome, then restart.
        if ! is_running "$XVFB_PID" "Xvfb"; then
            stop_services
            stop_chrome
            start_proc "$XVFB_PID" Xvfb "$DISPLAY_VAR" \
                -screen 0 "${MAX_FB_W}x${MAX_FB_H}x24" -ac
            wait_for_xvfb
            # Apply the requested resolution via xrandr now that Xvfb is fresh.
            apply_resolution "$SCREEN_W" "$SCREEN_H" || true
            echo "$WANT_RES" > "$RES_FILE"
        else
            # Xvfb is up — ensure resolution file is current.
            echo "$WANT_RES" > "$RES_FILE"
        fi

        # Window manager — required for Chrome to receive keyboard/scroll/focus events
        if ! is_running "$WM_PID" "fluxbox"; then
            start_proc "$WM_PID" env DISPLAY="$DISPLAY_VAR" fluxbox -display "$DISPLAY_VAR"
            sleep 1
        fi

        # Clipboard sync — keeps PRIMARY and CLIPBOARD selections in sync
        if command -v autocutsel >/dev/null 2>&1; then
            if ! is_running "$AUTOCUTSEL_PID" "autocutsel"; then
                start_proc "$AUTOCUTSEL_PID" env DISPLAY="$DISPLAY_VAR" autocutsel -fork
            fi
            if ! is_running "$AUTOCUTSEL_PRI_PID" "autocutsel"; then
                start_proc "$AUTOCUTSEL_PRI_PID" env DISPLAY="$DISPLAY_VAR" autocutsel -s PRIMARY -fork
            fi
        fi

        if ! is_running "$VNC_PID" "x11vnc"; then
            start_proc "$VNC_PID" x11vnc \
                -display "$DISPLAY_VAR" \
                -rfbport "$VNC_PORT" \
                -nopw -forever -quiet \
                -localhost -shared \
                -noxdamage \
                -xkb \
                -repeat
            wait_for_port "$VNC_PORT"
        fi

        NOVNC_WEB=""
        for d in /usr/share/novnc /usr/local/share/novnc; do
            [ -d "$d" ] && { NOVNC_WEB="$d"; break; }
        done
        if [ -z "$NOVNC_WEB" ]; then
            echo "ERROR: noVNC web directory not found"
            exit 1
        fi

        if ! is_running "$NOVNC_PID" "websockify"; then
            start_proc "$NOVNC_PID" websockify \
                --web "$NOVNC_WEB" \
                "127.0.0.1:$NOVNC_PORT" "127.0.0.1:$VNC_PORT"
            wait_for_port "$NOVNC_PORT"
            if ! is_running "$NOVNC_PID" "websockify"; then
                echo "ERROR: websockify failed to start (port $NOVNC_PORT may be in use)"
                exit 1
            fi
        fi

        # Release lock now that all services are confirmed running

        # Launch Chrome only if it is not already running — NEVER kill it.
        if ! is_running "$CHROME_PID" "chrome"; then
            mkdir -p "$CHROME_PROFILE"
            rm -f "$CHROME_PROFILE/SingletonLock" \
                  "$CHROME_PROFILE/SingletonSocket" \
                  "$CHROME_PROFILE/SingletonCookie"
            CHROME_BIN=$(command -v google-chrome-stable 2>/dev/null \
                      || command -v google-chrome 2>/dev/null \
                      || command -v chromium-browser 2>/dev/null \
                      || command -v chromium 2>/dev/null)
            if [ -z "$CHROME_BIN" ]; then
                echo "ERROR: no Chrome/Chromium binary found"
                exit 1
            fi
            start_proc "$CHROME_PID" env DISPLAY="$DISPLAY_VAR" "$CHROME_BIN" \
                --user-data-dir="$CHROME_PROFILE" \
                --profile-directory=Default \
                --no-first-run \
                --no-default-browser-check \
                --disable-sync \
                --disable-session-crashed-bubble \
                --password-store=basic \
                --disable-features=TranslateUI,ChromeWhatsNewUI,PrivacySandboxSettings4 \
                --use-gl=angle \
                --use-angle=swiftshader-webgl \
                --enable-unsafe-swiftshader \
                --no-sandbox \
                --disable-dev-shm-usage \
                --disable-background-timer-throttling \
                --disable-backgrounding-occluded-windows \
                --disable-renderer-backgrounding \
                --disable-notifications \
                --disable-infobars \
                --window-size="${SCREEN_W},${SCREEN_H}" \
                --window-position=0,0 \
                "https://claude.ai/design"
        fi

        echo "NOVNC_PORT=$NOVNC_PORT"
        echo "OK"
        ;;

    stop)
        stop_chrome
        stop_services
        rm -f "$RES_FILE" "$KICKED_FILE"
        echo "STOPPED"
        ;;

    status)
        if is_running "$NOVNC_PID" "websockify"; then
            echo "NOVNC_PORT=$NOVNC_PORT"
            echo "RUNNING"
        else
            echo "STOPPED"
        fi
        ;;

    check-kicked)
        if mv "$KICKED_FILE" "${KICKED_FILE}.consumed" 2>/dev/null; then
            rm -f "${KICKED_FILE}.consumed"
            echo "KICKED"
        else
            echo "OK"
        fi
        ;;

    *)
        echo "Usage: designer-start [start W H | stop | status | check-kicked]"
        exit 1
        ;;
esac