$ErrorActionPreference = 'Stop'
$repoWin = 'D:\Smart\Claude-Code-Server\scripts\client\windows'
$repoClient = 'D:\Smart\Claude-Code-Server\scripts\client'
$desk = 'C:\Users\Smart\Desktop\Claude-Connect'
if (-not (Test-Path $desk)) { throw "missing $desk" }

# Flat Desktop layout: many files live at Claude-Connect\ root
$map = @(
  @{ Src = (Join-Path $repoWin 'connect.ps1'); Dst = (Join-Path $desk 'connect.ps1') },
  @{ Src = (Join-Path $repoWin 'connect.bat'); Dst = (Join-Path $desk 'connect.bat') },
  @{ Src = (Join-Path $repoWin 'connect-boot.ps1'); Dst = (Join-Path $desk 'connect-boot.ps1') },
  @{ Src = (Join-Path $repoWin 'connect-bootstrap.ps1'); Dst = (Join-Path $desk 'connect-bootstrap.ps1') },
  @{ Src = (Join-Path $repoWin 'connect-heal.ps1'); Dst = (Join-Path $desk 'connect-heal.ps1') },
  @{ Src = (Join-Path $repoWin 'connect-update.ps1'); Dst = (Join-Path $desk 'connect-update.ps1') },
  @{ Src = (Join-Path $repoWin 'connect-preflight.ps1'); Dst = (Join-Path $desk 'connect-preflight.ps1') },
  @{ Src = (Join-Path $repoWin 'connect-version.txt'); Dst = (Join-Path $desk 'connect-version.txt') },
  @{ Src = (Join-Path $repoWin 'windows-mcp-laptop.ps1'); Dst = (Join-Path $desk 'windows-mcp-laptop.ps1') },
  @{ Src = (Join-Path $repoWin 'cursor-proxy-sidecar.ps1'); Dst = (Join-Path $desk 'cursor-proxy-sidecar.ps1') },
  @{ Src = (Join-Path $repoClient 'git-mode.ps1'); Dst = (Join-Path $desk 'git-mode.ps1') },
  @{ Src = (Join-Path $repoClient 'connect-ui.ps1'); Dst = (Join-Path $desk 'connect-ui.ps1') },
  @{ Src = (Join-Path $repoClient 'editor-launch.ps1'); Dst = (Join-Path $desk 'editor-launch.ps1') },
  @{ Src = (Join-Path $repoClient 'cursor-auth-laptop.ps1'); Dst = (Join-Path $desk 'cursor-auth-laptop.ps1') },
  @{ Src = (Join-Path $repoClient 'cursor-profile-db-tool.ps1'); Dst = (Join-Path $desk 'cursor-profile-db-tool.ps1') }
)

$sha = [System.Security.Cryptography.SHA256]::Create()
function Get-Sha([string]$p) {
  if (-not (Test-Path -LiteralPath $p)) { return 'MISSING' }
  $bytes = [IO.File]::ReadAllBytes($p)
  return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').Substring(0,12)
}

$synced = 0; $skipped = 0; $missingSrc = 0
foreach ($m in $map) {
  if (-not (Test-Path -LiteralPath $m.Src)) { Write-Host ("MISS_SRC {0}" -f $m.Src); $missingSrc++; continue }
  $before = Get-Sha $m.Dst
  $srcSha = Get-Sha $m.Src
  if ($before -eq $srcSha) { Write-Host ("OK_SAME {0}" -f (Split-Path $m.Dst -Leaf)); $skipped++; continue }
  Copy-Item -LiteralPath $m.Src -Destination $m.Dst -Force
  $after = Get-Sha $m.Dst
  Write-Host ("SYNC {0} {1}->{2}" -f (Split-Path $m.Dst -Leaf), $before, $after)
  $synced++
}

# Policy file if Desktop has one
$polSrc = 'D:\Smart\Claude-Code-Server\scripts\server\client-update-policy.json'
$polDst = Join-Path $desk 'client-update-policy.json'
if (Test-Path $polSrc) {
  Copy-Item -LiteralPath $polSrc -Destination $polDst -Force
  Write-Host 'SYNC client-update-policy.json'
}

# Markers after sync
$gm = Get-Content (Join-Path $desk 'git-mode.ps1') -Raw
$ui = Get-Content (Join-Path $desk 'connect-ui.ps1') -Raw
$cp = Get-Content (Join-Path $desk 'connect.ps1') -Raw
Write-Host ("desk_git sibling=" + [bool]($gm -match 'Get-SiblingConnectTunnelPids'))
Write-Host ("desk_git ACTIVE_MOUNT_GUARD=" + [bool]($gm -match 'ACTIVE_MOUNT_GUARD'))
Write-Host ("desk_git skip_sibling=" + [bool]($gm -match 'skip_sibling'))
Write-Host ("desk_ui forbid_shrink=" + [bool]($ui -match 'forbid_shrink'))
Write-Host ("desk_connect ver=" + $(if ($cp -match "ConnectVersion = '([^']+)'") { $Matches[1] } else { '?' }))
Write-Host ("synced=$synced same=$skipped miss_src=$missingSrc")

# Disable live Sepidz connect.bat under claude-publish extract
$sepBat = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-sepidz\claude-code\windows\connect.bat'
if (Test-Path -LiteralPath $sepBat) {
  $dis = $sepBat + '.DISABLED'
  if (Test-Path -LiteralPath $dis) { Remove-Item -LiteralPath $dis -Force }
  Rename-Item -LiteralPath $sepBat -NewName 'connect.bat.DISABLED' -Force
  Write-Host "DISABLED $sepBat"
} else {
  Write-Host 'SEPIDZ_BAT_ALREADY_GONE_OR_DISABLED'
}

# List any remaining live sepidz connect.bat
Get-ChildItem (Join-Path $env:USERPROFILE 'Desktop') -Recurse -Filter 'connect.bat' -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -match 'sepidz|Sepidz' -and $_.Name -eq 'connect.bat' } |
  ForEach-Object { Write-Host ("STILL_LIVE_SEPIDZ " + $_.FullName) }
