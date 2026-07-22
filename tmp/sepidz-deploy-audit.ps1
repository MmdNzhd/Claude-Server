#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-Location 'D:\Smart\Claude-Code-Server'
$raw = Get-Content -LiteralPath 'publish\sepidz-deploy.local.ps1' -Raw
$pw = [regex]::Match($raw, '(?m)^\s*\$SepidzSudoPassword\s*=\s*''([^'']*)''').Groups[1].Value
$sshUser = [regex]::Match($raw, '(?m)^\s*\$SepidzSshUser\s*=\s*''([^'']*)''').Groups[1].Value
if (-not $sshUser) { $sshUser = 'sepidz' }
if (-not $pw) { throw 'empty password' }
$target = "$sshUser@192.168.250.70"
$remoteDir = "/home/$sshUser/le-audit-deploy"
$sshOpts = @('-o','BatchMode=yes','-o','ConnectTimeout=20','-o','ControlMaster=no')

Write-Output ("=== stage to {0}:{1} ===" -f $target, $remoteDir)
& ssh @sshOpts $target "rm -rf $remoteDir && mkdir -p $remoteDir/cursor-hooks"
if ($LASTEXITCODE -ne 0) { throw 'mkdir failed' }

$files = @(
  @{ Local='scripts\server\laptop-exec.sh'; Remote="$remoteDir/laptop-exec.sh" },
  @{ Local='scripts\server\laptop-exec-setup.sh'; Remote="$remoteDir/laptop-exec-setup.sh" },
  @{ Local='scripts\server\commands\deploy-laptop-exec.sh'; Remote="$remoteDir/deploy-laptop-exec.sh" },
  @{ Local='scripts\server\cursor-hooks\laptop-exec-audit-log.sh'; Remote="$remoteDir/cursor-hooks/laptop-exec-audit-log.sh" },
  @{ Local='scripts\server\cursor-hooks\laptop-exec-guard.sh'; Remote="$remoteDir/cursor-hooks/laptop-exec-guard.sh" },
  @{ Local='scripts\server\cursor-hooks\laptop-exec-guard-wrap.sh'; Remote="$remoteDir/cursor-hooks/laptop-exec-guard-wrap.sh" },
  @{ Local='scripts\server\cursor-hooks\laptop-exec-session.sh'; Remote="$remoteDir/cursor-hooks/laptop-exec-session.sh" },
  @{ Local='scripts\server\cursor-hooks\laptop-exec-shell-scan.py'; Remote="$remoteDir/cursor-hooks/laptop-exec-shell-scan.py" },
  @{ Local='scripts\server\cursor-hooks\hooks-user.json'; Remote="$remoteDir/cursor-hooks/hooks-user.json" },
  @{ Local='scripts\server\cursor-hooks\hooks-project.json'; Remote="$remoteDir/cursor-hooks/hooks-project.json" }
)
foreach ($f in $files) {
  if (-not (Test-Path -LiteralPath $f.Local)) { throw "missing $($f.Local)" }
  & scp @sshOpts -q $f.Local ($target + ':' + $f.Remote)
  if ($LASTEXITCODE -ne 0) { throw "scp failed $($f.Local)" }
  Write-Output ("ok " + $f.Local)
}

$installSh = @'
#!/bin/bash
set -euo pipefail
SRC=/home/sepidz/le-audit-deploy
SERVER_DIR=/usr/local/lib/claude-server
atomic_install() {
  local mode="$1" src="$2" dst="$3" owner="${4:-}" group="${5:-}" tmp="${3}.new.$$"
  if [ -n "$owner" ]; then
    install -m "$mode" -o "$owner" -g "$group" "$src" "$tmp"
  else
    install -m "$mode" "$src" "$tmp"
  fi
  mv -f "$tmp" "$dst"
}
mkdir -p "$SERVER_DIR/cursor-hooks"
sed -i 's/\r$//' "$SRC/laptop-exec.sh" "$SRC/laptop-exec-setup.sh" "$SRC"/cursor-hooks/* || true
install -m 755 "$SRC/laptop-exec.sh" "$SERVER_DIR/laptop-exec.sh"
atomic_install 755 "$SERVER_DIR/laptop-exec.sh" /usr/local/bin/laptop-exec
install -m 755 "$SRC/laptop-exec-setup.sh" "$SERVER_DIR/laptop-exec-setup.sh"
atomic_install 755 "$SERVER_DIR/laptop-exec-setup.sh" /usr/local/bin/laptop-exec-setup
for hf in laptop-exec-audit-log.sh laptop-exec-guard.sh laptop-exec-guard-wrap.sh laptop-exec-session.sh laptop-exec-shell-scan.py hooks-user.json hooks-project.json; do
  [ -f "$SRC/cursor-hooks/$hf" ] || continue
  mode=644
  case "$hf" in *.sh|*.py) mode=755 ;; esac
  install -m "$mode" "$SRC/cursor-hooks/$hf" "$SERVER_DIR/cursor-hooks/$hf"
done
echo ===USERS===
getent passwd | awk -F: '$3 >= 1000 && $1 != "nobody" && $1 != "nfsnobody" { print $1 ":" $6 }' | while IFS=: read -r u h; do
  [ -n "$u" ] && [ -n "$h" ] && [ -d "$h" ] || continue
  install -d -m 755 -o "$u" -g "$u" "$h/.local/bin" "$h/.cursor/hooks" "$h/.claude/logs"
  atomic_install 755 /usr/local/bin/laptop-exec "$h/.local/bin/laptop-exec" "$u" "$u"
  atomic_install 755 /usr/local/bin/laptop-exec-setup "$h/.local/bin/laptop-exec-setup" "$u" "$u"
  for _hf in laptop-exec-audit-log.sh laptop-exec-guard.sh laptop-exec-guard-wrap.sh laptop-exec-session.sh laptop-exec-shell-scan.py; do
    [ -f "$SERVER_DIR/cursor-hooks/$_hf" ] || continue
    install -m 755 -o "$u" -g "$u" "$SERVER_DIR/cursor-hooks/$_hf" "$h/.cursor/hooks/$_hf"
  done
  sudo -u "$u" /usr/local/bin/laptop-exec-setup --user 2>/dev/null || true
  echo "ok user $u"
done
echo ===VERIFY===
wc -c /usr/local/bin/laptop-exec
grep -c _le_audit /usr/local/bin/laptop-exec || true
ls -la /usr/local/lib/claude-server/cursor-hooks/
test -f /usr/local/lib/claude-server/cursor-hooks/laptop-exec-audit-log.sh && echo AUDIT_HELPER=yes
sudo -u sepidz bash -c '
  LOGDIR="$HOME/.claude/logs"; mkdir -p "$LOGDIR"
  DAY=$(date -u +%Y%m%d)
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "$TS [INFO] LAPTOP_EXEC SMOKE sepidz-deploy-ok" >> "$LOGDIR/laptop-exec-$DAY.log"
  echo "$TS [multiagent] LAPTOP_EXEC SMOKE sepidz-deploy-ok" >> "$LOGDIR/connect-$DAY.log"
'
ls -la /home/sepidz/.claude/logs/ 2>&1 | tail -10
ls -la /home/smart/.cursor/hooks/ 2>&1 | head -15
ls -la /home/sepidz/.cursor/hooks/ 2>&1 | head -15
echo __DEPLOY_DONE__
'@

$localInstall = Join-Path $env:TEMP ('sepidz-install-' + [guid]::NewGuid().ToString('n') + '.sh')
[IO.File]::WriteAllText($localInstall, $installSh.Replace("`r`n","`n"), (New-Object Text.UTF8Encoding $false))
& scp @sshOpts -q $localInstall ($target + ':' + $remoteDir + '/install.sh')
if ($LASTEXITCODE -ne 0) { throw 'scp install.sh failed' }

Write-Output '=== sudo install ==='
$psi = New-Object Diagnostics.ProcessStartInfo
$psi.FileName = 'ssh.exe'
$psi.Arguments = "-o BatchMode=yes -o ConnectTimeout=20 -o ControlMaster=no $target `"sudo -S -p '' bash $remoteDir/install.sh`""
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$p = [Diagnostics.Process]::Start($psi)
$p.StandardInput.WriteLine($pw)
$p.StandardInput.Close()
$out = $p.StandardOutput.ReadToEnd()
$err = $p.StandardError.ReadToEnd()
if (-not $p.WaitForExit(120000)) { try { $p.Kill() } catch {}; throw 'timeout' }
Write-Output $out
foreach ($line in ($err -split "`n")) {
  if ($line -and ($line -notmatch '(?i)password')) { Write-Output ("ERR: " + $line) }
}
if ($out -notmatch '__DEPLOY_DONE__') { throw ("deploy incomplete exit=" + $p.ExitCode) }
Remove-Item -Force $localInstall -EA SilentlyContinue
Write-Output '=== OK ==='
