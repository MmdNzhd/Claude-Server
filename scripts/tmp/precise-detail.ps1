$ErrorActionPreference = 'Continue'

function Get-Markers($path, $label) {
  Write-Output "=== $label ==="
  if (-not (Test-Path $path)) { Write-Output 'MISS'; return }
  $lines = Get-Content $path
  for ($i=0; $i -lt $lines.Count; $i++) {
    $ln = $lines[$i]
    if ($ln -match 'Stop-CursorServerProfileTreeIfNeeded|preserve_open_windows|pre_launch_agent_or_new_window|LAUNCH_RETRY_NO_KILL|needKill') {
      Write-Output ("{0}:{1}" -f ($i+1), $ln.Trim())
    }
  }
}

Get-Markers 'D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1' 'REPO_editor-launch'

# pull Smart/Sepidz editor-launch snippets via ssh
function RemoteMarkers($label,$h,$u) {
  Write-Output "=== REMOTE_$label ==="
  $key = Join-Path $env:USERPROFILE '.ssh\claude_laptop'
  $args = @('-i',$key,'-o','BatchMode=yes','-o','ConnectTimeout=8','-o','StrictHostKeyChecking=accept-new', "${u}@${h}", 'grep -nE "Stop-CursorServerProfileTreeIfNeeded|preserve_open_windows|pre_launch_agent_or_new_window|LAUNCH_RETRY_NO_KILL|needKill" /usr/local/share/claude-client/editor-launch.ps1')
  $p = Start-Process -FilePath ssh -ArgumentList $args -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\rm-$label.out" -RedirectStandardError "$env:TEMP\rm-$label.err"
  [void]$p.WaitForExit(12000)
  if (Test-Path "$env:TEMP\rm-$label.out") { Get-Content "$env:TEMP\rm-$label.out" }
}
RemoteMarkers 'SMART' '192.168.210.240' 'smart'
RemoteMarkers 'SEPIDZ' '192.168.250.70' 'sepidz'

Write-Output '=== DESKTOP_STALE_PACKS ==='
$desk = 'C:\Users\Smart\Desktop\claude-publish'
if (Test-Path $desk) {
  Get-ChildItem $desk -Directory | ForEach-Object {
    $vfiles = Get-ChildItem $_.FullName -Recurse -Filter connect-version.txt -EA SilentlyContinue
    foreach ($vf in $vfiles) {
      $ver = (Get-Content $vf.FullName -Raw).Trim()
      $el = Join-Path $vf.DirectoryName 'editor-launch.ps1'
      $force = 'n/a'
      if (Test-Path $el) {
        $c = Get-Content $el -Raw
        $force = ([regex]::Matches($c,'pre_launch_agent_or_new_window')).Count
      }
      Write-Output ("{0} | ver={1} | force_marker={2} | {3}" -f $_.Name, $ver, $force, $vf.FullName)
    }
  }
}

Write-Output '=== UPDATE_COMPARE ==='
$up = 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-update.ps1'
if (Test-Path $up) {
  Select-String -Path $up -Pattern 'Compare|newer|Version|Remote|Local|update' | Select-Object -First 40 | ForEach-Object { ($_.LineNumber.ToString() + ':' + $_.Line.Trim()) }
}
