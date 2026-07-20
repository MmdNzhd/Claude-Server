param(
  [Parameter(Mandatory)][int]$Round,
  [string]$ReportLocal = ''
)
$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$ts=[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
$remote = @'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
S(){ printf '%s\n' "$PW" | sudo -S -p '' "$@"; }
ROUND=__ROUND__
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
OUT=/tmp/sepidz-round-$ROUND.json
PROBLEMS=()
FIXES=()
CHECKS=()

addc(){ CHECKS+=("$1"); }
addp(){ PROBLEMS+=("$1"); }
addf(){ FIXES+=("$1"); }

addc "bundle_version"
BUNDLE=$(cat /usr/local/share/claude-client/connect-version.txt 2>/dev/null || echo none)

addc "bin_markers"
for need in VSCODE_RESOLVING_ENVIRONMENT _heal_active_remount need_remount claude-last-active-mount; do
  if ! S grep -q "$need" /usr/local/bin/claude-automount /usr/local/bin/claude-self-heal /usr/local/bin/claude-watchdog 2>/dev/null; then
    addp "MISSING_MARKER:$need"
  fi
done

addc "cron_self_heal"
if [ ! -f /etc/cron.d/claude-self-heal ]; then addp "CRON_MISSING"; fi

addc "per_user_tunnel_mount_cursor"
declare -A TUN ACTIVE LAST WD MOUNTST CURSOR_SHELLFAIL CURSOR_LAST
USERS=(alit aminb farzadb hosseinb hosseinm nimaz zahrak)
for u in "${USERS[@]}"; do
  conf=/home/$u/.claude-connect.conf
  [ -f "$conf" ] || continue
  port=$(grep ^TUNNEL_PORT= "$conf" 2>/dev/null|cut -d= -f2|tr -d '\r')
  active=$(grep ^ACTIVE_MOUNT= "$conf" 2>/dev/null|cut -d= -f2|tr -d '\r')
  last=$(cat /home/$u/.cache/claude-last-active-mount 2>/dev/null|tr -d '\r\n')
  if [ -n "$port" ] && timeout 1 bash -c "exec 3<>/dev/tcp/127.0.0.1/$port" 2>/dev/null; then tun=UP; else tun=DOWN; fi
  TUN[$u]=$tun; ACTIVE[$u]=${active:-EMPTY}; LAST[$u]=${last:-NONE}
  if pgrep -u "$u" -f /usr/local/bin/claude-watchdog >/dev/null 2>&1; then WD[$u]=yes; else WD[$u]=no; fi
  ms=""
  for m in /home/$u/mounts/*; do
    [ -e "$m" ] || continue
    n=$(basename "$m")
    if grep -q " $m " /proc/mounts 2>/dev/null; then
      if timeout 2 ls "$m" >/dev/null 2>&1; then ms="${ms}${n}=OK;"; else ms="${ms}${n}=ZOMBIE;"; addp "ZOMBIE_MOUNT:$u/$n"; fi
    fi
  done
  MOUNTST[$u]=${ms:--}
  # tunnel UP but no mounts and has mounts.d
  if [ "$tun" = UP ] && [ "$ms" = "" ] && compgen -G "/home/$u/.claude-mounts.d/*.conf" >/dev/null 2>&1; then
    if [ -z "$active" ] || [ "$active" = EMPTY ]; then addp "TUNNEL_UP_EMPTY_ACTIVE:$u"; else addp "TUNNEL_UP_NO_MOUNT:$u/$active"; fi
  fi
  if [ "$tun" = UP ] && [ "${WD[$u]}" = no ]; then addp "TUNNEL_UP_NO_WATCHDOG:$u"; fi
  if [ "$tun" = UP ] && [ -z "$active" ]; then addp "ACTIVE_MOUNT_EMPTY:$u"; fi
  ra=$(ls -1dt /home/$u/.cursor-server/data/logs/*/remoteagent.log 2>/dev/null | head -1)
  if [ -n "$ra" ]; then
    CURSOR_LAST[$u]=$(stat -c %y "$ra" | cut -d. -f1)
    # only count shellfail if log mtime within last 2h
    age=$(( $(date +%s) - $(stat -c %Y "$ra") ))
    sf=$(grep -c "Unable to resolve your shell environment" "$ra" 2>/dev/null || echo 0)
    CURSOR_SHELLFAIL[$u]=$sf
    if [ "$age" -lt 7200 ] && [ "${sf:-0}" -gt 0 ]; then addp "CURSOR_SHELLENV_RECENT:$u count=$sf age_s=$age"; fi
  else
    CURSOR_LAST[$u]=none; CURSOR_SHELLFAIL[$u]=0
  fi
  # stuck connect bufs
  nbuf=$(find /home/$u/.claude/logs -name '.connect-buf-*.tmp' 2>/dev/null | wc -l)
  if [ "${nbuf:-0}" -gt 0 ]; then addp "STUCK_CONNECT_BUF:$u count=$nbuf"; fi
done

addc "farzad_tunnel_21006"
if ! ss -tln | grep -q ':21006 '; then
  # informational if down - not auto-fixable without laptop
  addp "FARZAD_TUNNEL_DOWN:21006 (needs laptop connect)"
fi

# ---- AUTO FIXES ----
addc "auto_heal_all_users"
for u in "${USERS[@]}"; do
  [ -f /home/$u/.claude-connect.conf ] || continue
  before_probs=$(printf '%s\n' "${PROBLEMS[@]}" | grep -c ":$u" || true)
  printf '%s\n' "$PW" | sudo -S -u "$u" -H /usr/local/bin/claude-self-heal --quiet 2>/dev/null || true
done
addf "ran claude-self-heal --quiet for all users with connect.conf"

# remount / watchdog for UP tunnels with problems
for u in "${USERS[@]}"; do
  [ "${TUN[$u]}" = UP ] || continue
  # finalize bufs already in self-heal
  if [ "${WD[$u]}" = no ]; then
    printf '%s\n' "$PW" | sudo -S -u "$u" -H bash -c 'nohup /usr/local/bin/claude-watchdog >/dev/null 2>&1 &' || true
    addf "started watchdog for $u"
    WD[$u]=yes
  fi
  active=${ACTIVE[$u]}
  if [ "$active" = EMPTY ] || [ -z "$active" ]; then
    printf '%s\n' "$PW" | sudo -S -u "$u" -H /usr/local/bin/claude-self-heal 2>/dev/null | tail -5 || true
    active=$(grep ^ACTIVE_MOUNT= /home/$u/.claude-connect.conf 2>/dev/null|cut -d= -f2|tr -d '\r')
    ACTIVE[$u]=${active:-EMPTY}
    addf "inferred/healed ACTIVE_MOUNT for $u -> ${ACTIVE[$u]}"
  fi
  # zombie or missing active mount
  if printf '%s\n' "${PROBLEMS[@]}" | grep -q "ZOMBIE_MOUNT:$u\|TUNNEL_UP_NO_MOUNT:$u"; then
    act=${ACTIVE[$u]}
    if [ -n "$act" ] && [ "$act" != EMPTY ]; then
      mp=/home/$u/mounts/$act
      S bash -c "pkill -u $u -f \"sshfs .*$mp\" 2>/dev/null || true; timeout 5 fusermount -uz $mp 2>/dev/null || timeout 5 umount -l $mp 2>/dev/null || true"
      printf '%s\n' "$PW" | sudo -S -u "$u" -H /usr/local/bin/claude-mount up "$act" 2>/dev/null | tail -5 || true
      if timeout 2 ls "$mp" >/dev/null 2>&1; then addf "remounted $u/$act OK"; else addp "REMOUNT_FAILED:$u/$act"; fi
    fi
  fi
done

# ensure bashrc timeout
addc "bashrc_timeout"
for u in "${USERS[@]}"; do
  br=/home/$u/.bashrc
  [ -f "$br" ] || continue
  grep -q claude-automount "$br" 2>/dev/null || continue
  if ! grep -qE 'timeout[[:space:]]+10' "$br"; then
    S sed -i -E 's@(\$HOME/\.local/bin/claude-automount|/usr/local/bin/claude-automount)[[:space:]]+2>/dev/null@timeout 10 \1 2>/dev/null@g' "$br"
    addf "wrapped bashrc timeout for $u"
    addp "BASHRC_NO_TIMEOUT:$u"
  fi
done

# ensure cron
if [ ! -f /etc/cron.d/claude-self-heal ]; then
  S bash -c 'cat >/etc/cron.d/claude-self-heal <<CRON
*/5 * * * * root for u in \$(ls /home); do id "\$u" >/dev/null 2>&1 || continue; [ -f /home/\$u/.claude-connect.conf ] || continue; sudo -u "\$u" -H /usr/local/bin/claude-self-heal --quiet >/dev/null 2>&1 || true; done
CRON
chmod 644 /etc/cron.d/claude-self-heal'
  addf "recreated /etc/cron.d/claude-self-heal"
fi

# re-scan mounts after fixes for summary
SUMMARY=""
for u in "${USERS[@]}"; do
  conf=/home/$u/.claude-connect.conf
  [ -f "$conf" ] || continue
  port=$(grep ^TUNNEL_PORT= "$conf"|cut -d= -f2|tr -d '\r')
  active=$(grep ^ACTIVE_MOUNT= "$conf"|cut -d= -f2|tr -d '\r')
  if [ -n "$port" ] && timeout 1 bash -c "exec 3<>/dev/tcp/127.0.0.1/$port" 2>/dev/null; then tun=UP; else tun=DOWN; fi
  ms=""
  for m in /home/$u/mounts/*; do
    [ -e "$m" ] || continue
    n=$(basename "$m")
    if grep -q " $m " /proc/mounts; then
      if timeout 2 ls "$m" >/dev/null 2>&1; then ms="${ms}${n}=OK;"; else ms="${ms}${n}=ZOMBIE;"; fi
    fi
  done
  wd=$(pgrep -u "$u" -f /usr/local/bin/claude-watchdog >/dev/null && echo y || echo n)
  SUMMARY+="$u tun=$tun act=${active:-E} m=${ms:--} wd=$wd; "
done

# emit machine + human
{
  echo "ROUND=$ROUND"
  echo "TS_UTC=$TS"
  echo "BUNDLE=$BUNDLE"
  echo "CHECKS<<EOF"
  printf '%s\n' "${CHECKS[@]}"
  echo "EOF"
  echo "PROBLEMS<<EOF"
  printf '%s\n' "${PROBLEMS[@]}"
  echo "EOF"
  echo "FIXES<<EOF"
  printf '%s\n' "${FIXES[@]}"
  echo "EOF"
  echo "SUMMARY=$SUMMARY"
} > "$OUT"
echo "WROTE $OUT"
echo "PROBLEM_COUNT=${#PROBLEMS[@]}"
echo "FIX_COUNT=${#FIXES[@]}"
cat "$OUT"
'@
$remote = $remote.Replace('__PWB64__',$pwB64).Replace('__ROUND__',"$Round") -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP "sepidz-round-$Round.out"
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=20','sepidz@192.168.250.70',("echo $b64 | base64 -d >/tmp/r$Round.sh && bash /tmp/r$Round.sh")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
if(-not $p.WaitForExit(300000)){ try{$p.Kill()}catch{}; throw "TIMEOUT round $Round" }
$text = Get-Content $out -Raw -EA SilentlyContinue
Write-Host $text
# also copy raw out beside report if path given
if ($ReportLocal) {
  $text | Set-Content -Path $ReportLocal -Encoding UTF8
}
