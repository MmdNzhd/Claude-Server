Write-Output "=== tools ==="
foreach ($name in @('uvx','windows-mcp','uv','node','npx')) {
  $c = Get-Command $name -ErrorAction SilentlyContinue
  if ($c) { Write-Output ("FOUND {0} -> {1}" -f $name, $c.Source) }
  else { Write-Output ("MISSING {0}" -f $name) }
}
Write-Output "=== python ==="
python --version
Write-Output "=== listen MCP-ish ports ==="
$found = $false
Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object {
  $_.LocalPort -in 8000,8001,24024,6274,3333,3847
} | ForEach-Object {
  $found = $true
  Write-Output ("LISTEN {0}:{1} pid={2}" -f $_.LocalAddress, $_.LocalPort, $_.OwningProcess)
}
if (-not $found) { Write-Output "LISTEN none" }
Write-Output "=== dirs ==="
Write-Output ("windows-mcp dir exists: {0}" -f (Test-Path "$env:USERPROFILE\.windows-mcp"))
Write-Output ("desktop-commander dir exists: {0}" -f (Test-Path "$env:USERPROFILE\.desktop-commander"))
$sched = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -match 'windows-mcp|desktop-commander' }
if ($sched) { $sched | ForEach-Object { Write-Output ("TASK {0} state={1}" -f $_.TaskName, $_.State) } }
else { Write-Output "TASK none" }
Write-Output "=== try uvx windows-mcp --help (first lines) ==="
if (Get-Command uvx -ErrorAction SilentlyContinue) {
  & uvx windows-mcp --help 2>&1 | Select-Object -First 12
} else {
  Write-Output "skip: no uvx"
}
