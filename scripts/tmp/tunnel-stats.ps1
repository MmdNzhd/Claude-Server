$ErrorActionPreference='Continue'

function Get-Stats($path, $label) {
  if (-not (Test-Path $path)) { return [pscustomobject]@{Label=$label; Ok=$false; Note='missing'} }
  $raw = Get-Content $path -Raw
  $lines = $raw -split "`n"
  $c = {
    param($rx)
    ([regex]::Matches($raw, $rx, 'IgnoreCase')).Count
  }
  [pscustomobject]@{
    Label = $label
    Ok = $true
    Bytes = (Get-Item $path).Length
    Lines = $lines.Count
    SessionStart = (& $c 'session start v')
    SessionEnd = (& $c 'session end')
    TunnelDrop = (& $c 'TUNNEL_DROP')
    SoftFail = (& $c 'TUNNEL_SYNC soft_fail')
    TunnelSync = (& $c 'TUNNEL_SYNC')
    EnsureTunnel = (& $c 'ENSURE_TUNNEL')
    Orphan = (& $c 'ORPHAN_TUNNEL')
    Recovery = (& $c 'RECOVERY_BEGIN|fallthrough_recover|Begin-ConnectRecovery')
    TunnelDown = (& $c 'tunnel_down|reason=tunnel_down|alreadyDown')
    BannerMiss = (& $c 'banner_miss')
    UserQuit = (& $c 'user_quit|reason=user_quit')
  }
}

# Local forensic
$results = @()
$results += Get-Stats 'D:\Smart\Claude-Code-Server\scripts\tmp\farzad-connect-20260719.log' 'farzad-local-copy'

# Pull smart log from sepidz to local temp
$ssh = @('-o','BatchMode=yes','-o','ConnectTimeout=20','-o','IdentitiesOnly=yes','-o','IdentityAgent=none')
$localSmart = 'D:\Smart\Claude-Code-Server\scripts\tmp\sepidz-smart-connect-20260719.log'
& scp @($ssh + @('-q','claude-server-sepidz:/home/smart/.claude/logs/connect-20260719.log', $localSmart))
if ($LASTEXITCODE -eq 0 -and (Test-Path $localSmart)) {
  $results += Get-Stats $localSmart 'sepidz-smart'
} else {
  Write-Output "scp smart failed exit=$LASTEXITCODE"
}

# Try pull farzadb with sudo via sepidz deploy password (non-interactive)
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pw = Get-SepidzSudoPassword
# write remote helper that reads password from stdin once
$helper = @'
#!/bin/bash
read -r PW
export SUDO_ASKPASS=/bin/false
echo "$PW" | sudo -S -p "" bash -lc '
for u in farzadb smart alit aminb hosseinb hosseinm nimaz zahrak; do
  for d in 20260719 20260718 20260717; do
    f=/home/$u/.claude/logs/connect-$d.log
    if [ -f "$f" ]; then
      echo "FILE|$u|$d|$(wc -c < "$f")|$(wc -l < "$f")"
      echo -n "CNT|$u|$d|start="; grep -c "session start" "$f" || true
      echo -n "CNT|$u|$d|end="; grep -c "session end" "$f" || true
      echo -n "CNT|$u|$d|DROP="; grep -c "TUNNEL_DROP" "$f" || true
      echo -n "CNT|$u|$d|soft="; grep -c "TUNNEL_SYNC soft_fail" "$f" || true
      echo -n "CNT|$u|$d|SYNC="; grep -c "TUNNEL_SYNC" "$f" || true
      echo -n "CNT|$u|$d|ENSURE="; grep -c "ENSURE_TUNNEL" "$f" || true
      echo -n "CNT|$u|$d|ORPHAN="; grep -c "ORPHAN_TUNNEL" "$f" || true
      echo -n "CNT|$u|$d|RECOV="; grep -cE "RECOVERY_BEGIN|fallthrough_recover" "$f" || true
      echo -n "CNT|$u|$d|tdown="; grep -cE "tunnel_down|alreadyDown" "$f" || true
      echo -n "CNT|$u|$d|quit="; grep -c "user_quit" "$f" || true
    fi
  done
done
'
'@
$helperPath = 'D:\Smart\Claude-Code-Server\scripts\tmp\sudo-tunnel-count.sh'
[IO.File]::WriteAllText($helperPath, $helper.Replace("`r`n","`n"))
& scp @($ssh + @('-q', $helperPath, 'claude-server-sepidz:/tmp/sudo-tunnel-count.sh'))
$outFile = 'D:\Smart\Claude-Code-Server\scripts\tmp\sudo-tunnel-count.out'
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'ssh'
$psi.Arguments = ($ssh + @('claude-server-sepidz', 'bash /tmp/sudo-tunnel-count.sh')) -join ' '
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$p = [Diagnostics.Process]::Start($psi)
$p.StandardInput.WriteLine($pw)
$p.StandardInput.Close()
$stdout = $p.StandardOutput.ReadToEnd()
$stderr = $p.StandardError.ReadToEnd()
$p.WaitForExit(120000) | Out-Null
Set-Content -Path $outFile -Value $stdout -Encoding UTF8
Write-Output '=== SUDO COUNTS RAW ==='
Write-Output $stdout
if ($stderr) { Write-Output '=== STDERR ==='; Write-Output ($stderr.Substring(0,[Math]::Min(500,$stderr.Length))) }

Write-Output '=== LOCAL STATS ==='
$results | Format-List | Out-String | Write-Output

# Farzad detail: ENSURE lines meanings
Write-Output '=== FARZAD ENSURE/ORPHAN samples ==='
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\tmp\farzad-connect-20260719.log' -Pattern 'ENSURE_TUNNEL|ORPHAN_TUNNEL|TUNNEL_|alreadyDown|tunnel' |
  Select-Object -First 30 | ForEach-Object { $_.Line.Trim().Substring(0,[Math]::Min(220,$_.Line.Trim().Length)) }
