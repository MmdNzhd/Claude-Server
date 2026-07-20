$ErrorActionPreference = 'Stop'
$key = Join-Path $env:USERPROFILE '.ssh\claude_laptop'
$target = 'sepidz@192.168.250.70'
$cfgPath = 'D:\Smart\Claude-Code-Server\publish\sepidz-deploy.local.ps1'
$cfg = Get-Content $cfgPath -Raw
if ($cfg -notmatch "SepidzSudoPassword\s*=\s*'([^']+)'") { throw 'no SepidzSudoPassword' }
$pw = $Matches[1]
Write-Output "pw_len=$($pw.Length)"

# Test sudo works
$testOut = Join-Path $env:TEMP 'sepidz-sudo-test.out'
$testErr = Join-Path $env:TEMP 'sepidz-sudo-test.err'
# Feed password via stdin to remote sudo -S
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'ssh'
$psi.Arguments = "-o ControlMaster=no -i `"$key`" -o BatchMode=yes -o ConnectTimeout=20 $target `"sudo -S -p '' id`""
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$p = [System.Diagnostics.Process]::Start($psi)
$p.StandardInput.WriteLine($pw)
$p.StandardInput.Close()
$stdout = $p.StandardOutput.ReadToEnd()
$stderr = $p.StandardError.ReadToEnd()
$p.WaitForExit(20000) | Out-Null
Write-Output "sudo_id_exit=$($p.ExitCode)"
Write-Output "sudo_id_out=$stdout"
Write-Output "sudo_id_err=$($stderr.Substring(0, [Math]::Min(200, $stderr.Length)))"

# Write remote list script without $ vars that PS expands - use base64
$bash = @'
#!/bin/bash
set -e
echo HOST=$(hostname)
echo "=== passwd azin-like ==="
getent passwd | grep -iE 'azin|azeen|azhin|adin|nima' || true
echo "=== all homes ==="
ls /home
echo "=== connect logs 14d ==="
find /home -path '*/.claude/logs/connect-*.log' -mtime -14 -printf '%T+ %u %p %s\n' 2>/dev/null | sort -r | head -60
echo "=== diag 14d ==="
find /home -path '*/.claude/logs/laptop-ssh*' -mtime -14 -printf '%T+ %u %p %s\n' 2>/dev/null | sort -r | head -30
echo "=== connect.conf ==="
for d in /home/*; do
  f="$d/.claude-connect.conf"
  if [ -f "$f" ]; then
    echo "---- $(basename "$d") ----"
    cat "$f"
  fi
done
echo "=== last connect per user ==="
for d in /home/*; do
  u=$(basename "$d")
  latest=$(ls -t "$d"/.claude/logs/connect-*.log 2>/dev/null | head -1)
  if [ -n "$latest" ]; then
    echo "USER=$u FILE=$latest"
    # show identity lines
    grep -E 'SERVER_USER|LAPTOP_USER|VERDICT|SESSION_STATUS|CLIENT_VERSION|hostname|ERROR|FAIL|WARN|CURSOR_NOT' "$latest" 2>/dev/null | head -40
    echo "---"
  fi
done
'@

$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bash))
$remoteCmd = "echo $b64 | base64 -d > /tmp/sepidz-azin-list.sh && chmod 700 /tmp/sepidz-azin-list.sh && printf '%s\n' " + "'" + ($pw -replace "'","'\''") + "'" + " | sudo -S -p '' bash /tmp/sepidz-azin-list.sh"

$psi2 = New-Object System.Diagnostics.ProcessStartInfo
$psi2.FileName = 'ssh'
$psi2.Arguments = "-o ControlMaster=no -i `"$key`" -o BatchMode=yes -o ConnectTimeout=30 $target `"$remoteCmd`""
$psi2.RedirectStandardOutput = $true
$psi2.RedirectStandardError = $true
$psi2.UseShellExecute = $false
$p2 = [System.Diagnostics.Process]::Start($psi2)
$out2 = $p2.StandardOutput.ReadToEnd()
$err2 = $p2.StandardError.ReadToEnd()
$p2.WaitForExit(60000) | Out-Null
Write-Output "list_exit=$($p2.ExitCode)"
Write-Output $out2
if ($err2) {
  Write-Output '---stderr---'
  # redact password if echoed
  ($err2 -replace [regex]::Escape($pw), '***')
}
