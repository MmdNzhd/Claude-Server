$ErrorActionPreference = 'Continue'
Write-Output '=== CRED ==='
$cred = 'D:\Smart\Claude-Code-Server\publish\sepidz-deploy.local.ps1'
if (Test-Path $cred) {
  Get-Content $cred | ForEach-Object { if ($_ -match 'Pass|password|User|user') { ($_ -replace '(?i)(password|pass)\s*=\s*.+','$1=***') } else { $_ } }
} else { Write-Output 'no cred file' }

# Probe via plink if available, else ssh with keys listed
Write-Output '=== TOOLS ==='
Write-Output ("plink=" + [bool](Get-Command plink -EA SilentlyContinue))
Write-Output ("sshpass=" + [bool](Get-Command sshpass -EA SilentlyContinue))
Get-ChildItem "$env:USERPROFILE\.ssh" -ErrorAction SilentlyContinue | Select-Object Name | ForEach-Object { $_.Name }

function QuickSsh($label,$h,$u,$extraArgs) {
  Write-Output "=== $label ==="
  $cmd = 'tr -d "\r\n" < /usr/local/share/claude-client/connect-version.txt; echo; EL=/usr/local/share/claude-client/editor-launch.ps1; printf "preserve=%s\n" "$(grep -c preserve_open_windows "$EL" 2>/dev/null || echo 0)"; printf "pre_launch_force=%s\n" "$(grep -c pre_launch_agent_or_new_window "$EL" 2>/dev/null || echo 0)"; printf "retry_no_kill=%s\n" "$(grep -c LAUNCH_RETRY_NO_KILL "$EL" 2>/dev/null || echo 0)"; printf "force_calls=%s\n" "$(grep -Ec "Stop-CursorServerProfileTreeIfNeeded.*-Force" "$EL" 2>/dev/null || echo 0)"'
  $all = @('-o','BatchMode=yes','-o','ConnectTimeout=6','-o','StrictHostKeyChecking=accept-new') + $extraArgs + @("${u}@${h}", $cmd)
  $p = Start-Process -FilePath ssh -ArgumentList $all -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\ssh-$label.out" -RedirectStandardError "$env:TEMP\ssh-$label.err"
  if (-not $p.WaitForExit(10000)) { try { $p.Kill() } catch {}; Write-Output 'TIMEOUT'; }
  else { Write-Output ("exit=" + $p.ExitCode) }
  if (Test-Path "$env:TEMP\ssh-$label.out") { Get-Content "$env:TEMP\ssh-$label.out" }
  if (Test-Path "$env:TEMP\ssh-$label.err") { Write-Output '---stderr---'; Get-Content "$env:TEMP\ssh-$label.err" }
}

$k1 = Join-Path $env:USERPROFILE '.ssh\id_rsa'
$k2 = Join-Path $env:USERPROFILE '.ssh\claude_laptop'
$extra = @()
if (Test-Path $k2) { $extra += @('-i',$k2) }
elseif (Test-Path $k1) { $extra += @('-i',$k1) }
QuickSsh 'SEPIDZ' '192.168.250.70' 'sepidz' $extra
QuickSsh 'SMART' '192.168.210.240' 'smart' $extra
