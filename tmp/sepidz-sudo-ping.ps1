#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$raw = Get-Content -LiteralPath 'publish\sepidz-deploy.local.ps1' -Raw
$pw = [regex]::Match($raw, '(?m)^\s*\$SepidzSudoPassword\s*=\s*''([^'']*)''').Groups[1].Value
if (-not $pw) { throw 'empty pw' }
Write-Host ("user=sepidz pw_len=" + $pw.Length)
$target = 'sepidz@192.168.250.70'
# Use SSH with remote bash reading password from a here-string sent via stdin of ssh? 
# Safer: write pw to temp file locally, scp is bad. Use printf carefully.
$psi = New-Object Diagnostics.ProcessStartInfo
$psi.FileName = 'ssh.exe'
$psi.Arguments = "-o BatchMode=yes -o ConnectTimeout=15 -o ControlMaster=no -o ControlPath=none $target bash -lc `"whoami; sudo -n true 2>/dev/null && echo SUDO_NOPASS_OK || echo SUDO_NEEDS_PASS; printf '%s\n' '$pw' | sudo -S -p '' id; echo RC=\$?`""
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$p = [Diagnostics.Process]::Start($psi)
if (-not $p.WaitForExit(25000)) { try { $p.Kill() } catch {}; throw 'timeout' }
$out = $p.StandardOutput.ReadToEnd()
$err = $p.StandardError.ReadToEnd()
Write-Host $out
foreach ($line in ($err -split "`n")) {
  if ($line -and ($line -notmatch '(?i)^\[sudo\] password')) { Write-Host ("ERR: " + $line) }
}
Write-Host ("EXIT=" + $p.ExitCode)
