$ErrorActionPreference = 'Continue'
$pat = "ConnectVersion = '20260722.40'"
$candidates = @()

# Desktop Claude-Connect
$desk = [Environment]::GetFolderPath('Desktop')
foreach ($p in @(
  (Join-Path $desk 'Claude-Connect\connect.ps1'),
  (Join-Path $desk 'Claude-Connect\windows\connect.ps1'),
  (Join-Path $desk 'claude-publish\claude-code-client\windows\connect.ps1')
)) {
  if (Test-Path $p) {
    $t = Get-Content $p -Raw -ErrorAction SilentlyContinue
    if ($t -and $t.Contains($pat)) { $candidates += $p; Write-Host "DESK_HIT $p" }
    elseif ($t -match "ConnectVersion = '([^']+)'") { Write-Host "DESK_VER $($Matches[1]) $p" }
  }
}

# Cursor History
$hist = Join-Path $env:APPDATA 'Cursor\User\History'
if (Test-Path $hist) {
  Write-Host "Scanning $hist ..."
  Get-ChildItem $hist -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
    try {
      # quick size filter
      if ($_.Length -lt 50000 -or $_.Length -gt 500000) { return }
      $head = Get-Content $_.FullName -TotalCount 200 -ErrorAction SilentlyContinue | Out-String
      if ($head -match "ConnectVersion = '20260722\.40'") {
        Write-Host "HIST_HIT $($_.FullName)"
        $candidates += $_.FullName
      }
    } catch {}
  }
}

# Local AppData ClaudeServerCursorProfile not relevant
# Check Temp
Get-ChildItem $env:TEMP -Filter 'connect.ps1*' -ErrorAction SilentlyContinue | ForEach-Object {
  Write-Host "TEMP $($_.FullName) $($_.Length)"
}

# Repo tmp
$repoTmp = 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1.tmpfix'
if (Test-Path $repoTmp) { Write-Host "REPO_TMP $repoTmp" }

Write-Host ("candidates=" + $candidates.Count)
$candidates | ForEach-Object { Write-Host $_ }
