$ErrorActionPreference = 'Continue'
$key = Join-Path $env:USERPROFILE '.ssh\claude_laptop'

function RunRemote($label,$h,$u,$cmd) {
  Write-Output "=== $label ==="
  $a = @('-i',$key,'-o','BatchMode=yes','-o','ConnectTimeout=8','-o','StrictHostKeyChecking=accept-new', "${u}@${h}", $cmd)
  $out = "$env:TEMP\r2-$label.out"; $err = "$env:TEMP\r2-$label.err"
  $p = Start-Process -FilePath ssh -ArgumentList $a -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
  [void]$p.WaitForExit(15000)
  Write-Output ("exit=" + $p.ExitCode)
  if (Test-Path $out) { Get-Content $out }
  if (Test-Path $err) { $e = Get-Content $err; if ($e) { Write-Output 'ERR:'; $e } }
}

$g = 'grep -nE Stop-CursorServerProfileTreeIfNeeded\|preserve_open_windows\|pre_launch_agent_or_new_window\|LAUNCH_RETRY_NO_KILL\|needKill /usr/local/share/claude-client/editor-launch.ps1 | head -40'
RunRemote 'SMART_LINES' '192.168.210.240' 'smart' $g
RunRemote 'SEPIDZ_LINES' '192.168.250.70' 'sepidz' $g

# Mac version consistency on desktop/repo
Write-Output '=== VERSION_MATRIX ==='
$paths = @(
  'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-version.txt',
  'D:\Smart\Claude-Code-Server\scripts\client\mac\connect-version.txt',
  'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260715\windows\connect-version.txt',
  'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260715\mac\connect-version.txt',
  'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260715\claude-code\windows\connect-version.txt',
  'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260715\claude-code\mac\connect-version.txt'
)
foreach ($p in $paths) {
  if (Test-Path $p) { Write-Output (((Get-Content $p -Raw).Trim()) + ' | ' + $p) } else { Write-Output ("MISS | " + $p) }
}

# Does connect.ps1 ScriptConnectVersion match?
Write-Output '=== CONNECT_PS1_VERSION ==='
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1' -Pattern 'ScriptConnectVersion\s*=' | ForEach-Object { $_.Line.Trim() }
Select-String -Path 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260715\windows\connect.ps1' -Pattern 'ScriptConnectVersion\s*=' | ForEach-Object { $_.Line.Trim() }
