$ErrorActionPreference = 'Continue'
$targets = @(
  @{ Name = 'REPO'; Path = 'D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1'; Ver = 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-version.txt' },
  @{ Name = 'DESKTOP_SMART'; Path = 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260715\windows\editor-launch.ps1'; Ver = 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260715\windows\connect-version.txt' },
  @{ Name = 'DESKTOP_SEPIDZ'; Path = 'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260715\claude-code\windows\editor-launch.ps1'; Ver = 'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260715\claude-code\windows\connect-version.txt' }
)
foreach ($t in $targets) {
  Write-Output "=== $($t.Name) ==="
  if (-not (Test-Path $t.Path)) { Write-Output 'MISS editor-launch'; continue }
  if (Test-Path $t.Ver) { Write-Output ("version=" + ((Get-Content $t.Ver -Raw).Trim())) } else { Write-Output 'version=MISS' }
  $c = Get-Content $t.Path -Raw
  Write-Output ("preserve_open_windows=" + ([regex]::Matches($c, 'preserve_open_windows')).Count)
  Write-Output ("pre_launch_agent_or_new_window=" + ([regex]::Matches($c, 'pre_launch_agent_or_new_window')).Count)
  Write-Output ("LAUNCH_RETRY_NO_KILL=" + ([regex]::Matches($c, 'LAUNCH_RETRY_NO_KILL')).Count)
  Write-Output ("Force_tree_kill_calls=" + ([regex]::Matches($c, 'Stop-CursorServerProfileTreeIfNeeded[^\r\n]*-Force')).Count)
  Write-Output ("Stop-CursorServerProfileTreeIfNeeded_total=" + ([regex]::Matches($c, 'Stop-CursorServerProfileTreeIfNeeded')).Count)
}

# Installed client update cache if present
$cacheDirs = @(
  "$env:LOCALAPPDATA\ClaudeCodeClient",
  "$env:LOCALAPPDATA\claude-code-client",
  "$env:USERPROFILE\.config\claude-connect"
)
Write-Output '=== LOCAL_CLIENT_CACHE ==='
foreach ($d in $cacheDirs) {
  if (Test-Path $d) {
    Write-Output "DIR $d"
    Get-ChildItem $d -Recurse -Filter 'connect-version.txt' -ErrorAction SilentlyContinue | ForEach-Object {
      Write-Output ("  " + $_.FullName + " => " + ((Get-Content $_.FullName -Raw).Trim()))
    }
    Get-ChildItem $d -Recurse -Filter 'editor-launch.ps1' -ErrorAction SilentlyContinue | ForEach-Object {
      $c = Get-Content $_.FullName -Raw
      Write-Output ("  " + $_.FullName)
      Write-Output ("    preserve=" + ([regex]::Matches($c,'preserve_open_windows')).Count + " force_marker=" + ([regex]::Matches($c,'pre_launch_agent_or_new_window')).Count)
    }
  }
}
