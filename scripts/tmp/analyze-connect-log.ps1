#Requires -Version 5.1
$ErrorActionPreference = 'Continue'
$path = 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows\connect.log'
if (-not (Test-Path $path)) {
  # also try common alternate locations
  $alts = @(
    'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\connect.log',
    (Join-Path $env:USERPROFILE '.config\claude-connect\connect.log'),
    (Join-Path $env:LOCALAPPDATA 'claude-connect\connect.log')
  )
  Write-Output "MISS primary: $path"
  foreach ($a in $alts) { Write-Output ("alt exists? {0} -> {1}" -f $a, (Test-Path $a)) }
  # search recent connect.log under Desktop publish
  Get-ChildItem (Join-Path $env:USERPROFILE 'Desktop\claude-publish') -Recurse -Filter 'connect.log' -EA SilentlyContinue |
    Select-Object -First 20 FullName, Length, LastWriteTime |
    ForEach-Object { Write-Output ("FOUND {0} len={1} mtime={2}" -f $_.FullName, $_.Length, $_.LastWriteTime) }
  exit 1
}

$i = Get-Item $path
Write-Output "=== FILE ==="
Write-Output ("path=$($i.FullName)")
Write-Output ("size=$($i.Length) mtime=$($i.LastWriteTime) ctime=$($i.CreationTime)")

$lines = Get-Content $path -ErrorAction Stop
Write-Output ("lines=$($lines.Count)")

Write-Output ''
Write-Output '=== HEAD (40) ==='
$lines | Select-Object -First 40 | ForEach-Object { $_ }

Write-Output ''
Write-Output '=== TAIL (80) ==='
$lines | Select-Object -Last 80 | ForEach-Object { $_ }

Write-Output ''
Write-Output '=== KEY COUNTS ==='
$patterns = @(
  'ConnectVersion|CONNECT_VERSION|Client version|v2026',
  '20260717\.1|20260715\.|20260714\.',
  'preserve_open_windows|LAUNCH_KILL_SKIP|LAUNCH_RETRY_NO_KILL|pre_launch_agent_or_new_window',
  'Stop-CursorServerProfileTreeIfNeeded|Force|kill',
  'ORPHAN|orphan',
  'ERROR|FAIL|Exception|Traceback|fatal',
  'WARN|warning',
  'sudo|deploy|bundle',
  'mount|sshfs|tunnel',
  'editor|cursor|new-window|Agent',
  'update|Updated to|Client update'
)
foreach ($pat in @(
  @{N='version_20260717.1'; P='20260717\.1'},
  @{N='version_20260715'; P='20260715\.'},
  @{N='version_old_20260714'; P='20260714\.'},
  @{N='LAUNCH_KILL_SKIP'; P='LAUNCH_KILL_SKIP'},
  @{N='preserve_open_windows'; P='preserve_open_windows'},
  @{N='LAUNCH_RETRY_NO_KILL'; P='LAUNCH_RETRY_NO_KILL'},
  @{N='pre_launch_force'; P='pre_launch_agent_or_new_window'},
  @{N='Stop-Cursor.*Force'; P='Stop-CursorServerProfileTreeIfNeeded.*Force|-Force'},
  @{N='ORPHAN'; P='ORPHAN'},
  @{N='ERROR'; P='\bERROR\b|\bFAIL\b|Exception'},
  @{N='WARN'; P='\bWARN\b|WARNING'},
  @{N='Client update'; P='Client update|Updated to'},
  @{N='tunnel'; P='tunnel|Tunnel'},
  @{N='mount'; P='mount|SSHFS|sshfs'},
  @{N='editor launch'; P='LAUNCH_|editor-launch|Open-Editor|Start-Cursor'}
)) {
  $c = ($lines | Select-String -Pattern $pat.P -AllMatches).Count
  Write-Output ("{0,-28} {1}" -f $pat.N, $c)
}

Write-Output ''
Write-Output '=== ALL VERSION MENTIONS ==='
$lines | Select-String -Pattern '2026071[0-9]\.\d+|ConnectVersion|Client version|Updated to|update available' |
  ForEach-Object { "{0}: {1}" -f $_.LineNumber, $_.Line.Trim() }

Write-Output ''
Write-Output '=== KILL / CURSOR RELATED ==='
$lines | Select-String -Pattern 'KILL|kill|Force|preserve_open|Cursor|profile|new.window|ORPHAN' -CaseSensitive:$false |
  Select-Object -Last 60 |
  ForEach-Object { "{0}: {1}" -f $_.LineNumber, $_.Line.Trim() }

Write-Output ''
Write-Output '=== ERROR / WARN LINES ==='
$lines | Select-String -Pattern '\bERROR\b|\bFAIL\b|Exception|Traceback|\bWARN\b|WARNING|fatal|denied|timeout|Timed out' -CaseSensitive:$false |
  Select-Object -Last 80 |
  ForEach-Object { "{0}: {1}" -f $_.LineNumber, $_.Line.Trim() }

Write-Output ''
Write-Output '=== SESSION BOUNDARIES (last 30 starts/ends) ==='
$lines | Select-String -Pattern '^=+|START|BEGIN|session|connect\.ps1|Disconnect|EXIT|cleanup|Already' -CaseSensitive:$false |
  Select-Object -Last 40 |
  ForEach-Object { "{0}: {1}" -f $_.LineNumber, $_.Line.Trim() }
