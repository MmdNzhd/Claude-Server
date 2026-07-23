#!/usr/bin/env bash
# xray-ensure-single.sh - Keep at most one xray process for the configured binary/config.
#
# Modes:
#   (default)     Keep systemd MainPID; kill other matching xray PIDs; restart unit if none.
#   --pre-start   Kill all matching xray PIDs (for systemd ExecStartPre). Do not restart.
#   --status      Print MainPID and matching PIDs; exit 1 if more than one match.
#
# Environment overrides:
#   XRAY_BIN      default: /home/smart/.local/bin/xray
#   XRAY_CFG      default: /home/smart/.local/etc/xray/config.json
#   XRAY_SERVICE  default: xray
#   XRAY_USER     default: smart
set -euo pipefail

XRAY_BIN="${XRAY_BIN:-/home/smart/.local/bin/xray}"
XRAY_CFG="${XRAY_CFG:-/home/smart/.local/etc/xray/config.json}"
SERVICE="${XRAY_SERVICE:-xray}"
XRAY_USER="${XRAY_USER:-smart}"
MODE=ensure

usage() {
  cat <<'USAGE'
Usage: xray-ensure-single [--pre-start|--status|-h]

Ensure a single xray instance for the configured binary/config.
  (default)    kill orphan duplicates; systemctl restart if MainPID missing
  --pre-start  kill all matching xray (ExecStartPre); do not restart
  --status     list MainPID + matching PIDs; exit 1 if duplicates
USAGE
}

case "${1:-}" in
  --pre-start) MODE=pre-start ;;
  --status) MODE=status ;;
  -h|--help)
    usage
    exit 0
    ;;
  "")
    ;;
  *)
    echo "xray-ensure-single: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
esac

is_matching_pid() {
  local pid="$1" cmd
  [[ -r "/proc/${pid}/cmdline" ]] || return 1
  cmd="$(tr '\0' ' ' <"/proc/${pid}/cmdline" 2>/dev/null || true)"
  [[ -n "$cmd" ]] || return 1
  [[ "$cmd" == *"$XRAY_CFG"* ]] || return 1
  # Prefer exact binary path; also accept basename-only cmdline.
  if [[ "$cmd" == *"$XRAY_BIN"* ]] || [[ "$cmd" == xray\ * ]] || [[ "$cmd" == */xray\ * ]]; then
    return 0
  fi
  return 1
}

list_matching_pids() {
  local pid
  for pid in $(pgrep -u "$XRAY_USER" -x xray 2>/dev/null || true); do
    if is_matching_pid "$pid"; then
      printf '%s\n' "$pid"
    fi
  done
}

main_pid() {
  local mp
  mp="$(systemctl show -p MainPID --value "$SERVICE" 2>/dev/null || echo 0)"
  if [[ -z "$mp" || "$mp" == "0" ]]; then
    echo ""
    return 0
  fi
  if kill -0 "$mp" 2>/dev/null; then
    echo "$mp"
  else
    echo ""
  fi
}

kill_pid() {
  local pid="$1"
  kill "$pid" 2>/dev/null || true
}

kill_pids() {
  local pid still=0
  for pid in "$@"; do
    [[ -n "$pid" ]] || continue
    kill_pid "$pid"
  done
  # Brief grace, then SIGKILL leftovers.
  sleep 0.3
  for pid in "$@"; do
    [[ -n "$pid" ]] || continue
    if kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null || true
      still=1
    fi
  done
  if [[ "$still" -eq 1 ]]; then
    sleep 0.1
  fi
}

status_report() {
  local mp matches
  mp="$(main_pid)"
  mapfile -t matches < <(list_matching_pids)
  echo "service=${SERVICE}"
  echo "MainPID=${mp:-0}"
  echo "matching_pids=${matches[*]:-}"
  echo "matching_count=${#matches[@]}"
  if [[ "${#matches[@]}" -gt 1 ]]; then
    return 1
  fi
  return 0
}

case "$MODE" in
  status)
    status_report
    exit $?
    ;;
  pre-start)
    mapfile -t matches < <(list_matching_pids)
    if [[ "${#matches[@]}" -gt 0 ]]; then
      echo "xray-ensure-single: pre-start killing PIDs: ${matches[*]}"
      kill_pids "${matches[@]}"
    fi
    exit 0
    ;;
  ensure)
    mp="$(main_pid)"
    mapfile -t matches < <(list_matching_pids)
    orphans=()
    for pid in "${matches[@]:-}"; do
      [[ -n "$pid" ]] || continue
      if [[ -n "$mp" && "$pid" == "$mp" ]]; then
        continue
      fi
      orphans+=("$pid")
    done
    if [[ "${#orphans[@]}" -gt 0 ]]; then
      echo "xray-ensure-single: killing orphan PIDs: ${orphans[*]} (keeping MainPID=${mp:-none})"
      kill_pids "${orphans[@]}"
    fi
    mp="$(main_pid)"
    if [[ -z "$mp" ]]; then
      echo "xray-ensure-single: no healthy MainPID; restarting ${SERVICE}"
      systemctl restart "$SERVICE"
    else
      echo "xray-ensure-single: ok MainPID=${mp}"
    fi
    status_report || true
    exit 0
    ;;
esac
