#!/usr/bin/env bash
# sudo-from-laptop - non-interactive sudo using gitignored passwords on the laptop.
#
# Agents MUST use this instead of prompting for a sudo password. Never print the password.
#
# Usage:
#   sudo-from-laptop [--smart|--sepidz] [-p PROJECT] -v
#   sudo-from-laptop [--smart|--sepidz] [-p PROJECT] -- <command...>
#
# Smart (default): local sudo via publish/smart-deploy.local.ps1 -> SmartSudoPassword
# Sepidz:          ssh + sudo via publish/sepidz-deploy.local.ps1 -> SepidzSudoPassword
#
# Env overrides: SMART_SUDO_PASSWORD, SEPIDZ_SUDO_PASSWORD, SEPIDZ_SSH_USER, SEPIDZ_SERVER_IP
#                LAPTOP_EXEC_DEPLOY_PROJECT (default: claude-code-server)

set -euo pipefail

TARGET="smart"
PROJECT="${LAPTOP_EXEC_DEPLOY_PROJECT:-claude-code-server}"
VALIDATE_ONLY=0
CMD=()

_die() { echo "sudo-from-laptop: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --smart) TARGET="smart"; shift ;;
    --sepidz) TARGET="sepidz"; shift ;;
    -p|--project)
      [ $# -ge 2 ] || _die "missing value for $1"
      PROJECT="$2"; shift 2 ;;
    -v|--validate) VALIDATE_ONLY=1; shift ;;
    --) shift; CMD=("$@"); break ;;
    -h|--help)
      sed -n '2,18p' "$0" | sed 's/^# \?//'
      exit 0 ;;
    *) CMD=("$@"); break ;;
  esac
done

command -v laptop-exec >/dev/null 2>&1 || _die "laptop-exec not on PATH"
# Avoid `grep -q | pipefail` (SIGPIPE → false DOWN when match is mid-stream).
_le_status="$(laptop-exec status 2>/dev/null || true)"
case "$_le_status" in
  *"tunnel:"*"UP"*) ;;
  *) _die "tunnel DOWN - run connect.bat/sh first" ;;
esac
unset _le_status

_extract_ps1() {
  local name="$1" val
  val=$(sed -n "s/^[[:space:]]*\$${name}[[:space:]]*=[[:space:]]*'\([^']*\)'.*/\1/p; s/^[[:space:]]*\$${name}[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n1)
  printf '%s' "$val"
}

_load_smart_pw() {
  if [ -n "${SMART_SUDO_PASSWORD:-}" ]; then printf '%s' "$SMART_SUDO_PASSWORD"; return 0; fi
  local raw
  raw="$(laptop-exec read -p "$PROJECT" publish/smart-deploy.local.ps1 2>/dev/null || true)"
  [ -n "$raw" ] || _die "cannot read publish/smart-deploy.local.ps1 (laptop-exec -p $PROJECT)"
  printf '%s' "$raw" | _extract_ps1 SmartSudoPassword
}

_load_sepidz_pw() {
  if [ -n "${SEPIDZ_SUDO_PASSWORD:-}" ]; then printf '%s' "$SEPIDZ_SUDO_PASSWORD"; return 0; fi
  local raw
  raw="$(laptop-exec read -p "$PROJECT" publish/sepidz-deploy.local.ps1 2>/dev/null || true)"
  [ -n "$raw" ] || _die "cannot read publish/sepidz-deploy.local.ps1 (laptop-exec -p $PROJECT)"
  printf '%s' "$raw" | _extract_ps1 SepidzSudoPassword
}

_load_sepidz_target() {
  local raw user host
  raw="$(laptop-exec read -p "$PROJECT" publish/sepidz-deploy.local.ps1 2>/dev/null || true)"
  user="${SEPIDZ_SSH_USER:-}"
  host="${SEPIDZ_SERVER_IP:-}"
  if [ -z "$user" ] && [ -n "$raw" ]; then
    user="$(printf '%s' "$raw" | _extract_ps1 SepidzSshUser)"
  fi
  user="${user:-sepidz}"
  host="${host:-192.168.250.70}"
  printf '%s@%s' "$user" "$host"
}

_auth_local() {
  local pw="$1"
  [ -n "$pw" ] || _die "empty SmartSudoPassword - set publish/smart-deploy.local.ps1 on laptop"
  if ! printf '%s\n' "$pw" | sudo -S -v >/dev/null 2>&1; then
    _die "sudo auth failed for Smart (check SmartSudoPassword)"
  fi
}

_run_smart() {
  local pw
  pw="$(_load_smart_pw)"
  _auth_local "$pw"
  unset pw
  if [ "$VALIDATE_ONLY" -eq 1 ]; then
    echo "sudo-from-laptop: smart auth OK (project=$PROJECT)"
    return 0
  fi
  [ "${#CMD[@]}" -gt 0 ] || _die "usage: sudo-from-laptop [--smart] -- <command...>"
  sudo "${CMD[@]}"
}

_run_sepidz() {
  local pw target qcmd
  pw="$(_load_sepidz_pw)"
  [ -n "$pw" ] || _die "empty SepidzSudoPassword - set publish/sepidz-deploy.local.ps1 on laptop"
  target="$(_load_sepidz_target)"
  if [ "$VALIDATE_ONLY" -eq 1 ]; then
    if printf '%s\n' "$pw" | ssh -o BatchMode=yes -o ConnectTimeout=15 "$target" \
      "sudo -S -v" >/dev/null 2>&1; then
      echo "sudo-from-laptop: sepidz auth OK (target=$target project=$PROJECT)"
      return 0
    fi
    _die "sudo auth failed for Sepidz ($target)"
  fi
  [ "${#CMD[@]}" -gt 0 ] || _die "usage: sudo-from-laptop --sepidz -- <command...>"
  qcmd="$(printf '%q ' "${CMD[@]}")"
  # SECURITY: password only on SSH stdin — never in remote command string / process list.
  remote_script=$(cat <<'RS'
set -euo pipefail
IFS= read -r -s PW || true
printf '%s\n' "$PW" | sudo -S -p '' -v >/dev/null
printf '%s\n' "$PW" | sudo -S -p '' bash -lc "$1"
RS
)
  # Pass qcmd as $1 to remote bash; password via ssh stdin (first line).
  if printf '%s\n' "$pw" | ssh -o BatchMode=yes -o ConnectTimeout=120 "$target" \
    "bash -c $(printf '%q' "$remote_script") _ $(printf '%q' "$qcmd")"; then
    return 0
  fi
  _die "sudo auth/exec failed for Sepidz ($target)"
}


case "$TARGET" in
  smart) _run_smart ;;
  sepidz) _run_sepidz ;;
  *) _die "unknown target $TARGET" ;;
esac
