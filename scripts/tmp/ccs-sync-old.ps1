$ErrorActionPreference = 'Stop'
$repoWin = (Resolve-Path 'scripts\client\windows').Path
$repoClient = (Resolve-Path 'scripts\client').Path
$files = @(
  @{ Src = (Join-Path $repoWin 'connect-update.ps1'); Name = 'connect-update.ps1' },
  @{ Src = (Join-Path $repoWin 'cursor-proxy-sidecar.ps1'); Name = 'cursor-proxy-sidecar.ps1' },
  @{ Src = (Join-Path $repoWin 'connect.ps1'); Name = 'connect.ps1' },
  @{ Src = (Join-Path $repoWin 'connect-version.txt'); Name = 'connect-version.txt' },
  @{ Src = (Join-Path $repoClient 'git-mode.ps1'); Name = 'git-mode.ps1' },
  @{ Src = (Join-Path $repoClient 'editor-launch.ps1'); Name = 'editor-launch.ps1' },
  @{ Src = (Join-Path $repoClient 'connect-ui.ps1'); Name = 'connect-ui.ps1' }
)
$targets = @(
  (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'),
  (Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260717\windows'),
  (Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260721\windows')
)
foreach ($t in $targets) {
  if (-not (Test-Path $t)) { Write-Host "SKIP missing $t"; continue }
  Write-Host "=== SYNC $t ==="
  foreach ($f in $files) {
    $dst = Join-Path $t $f.Name
    # Desktop Claude-Connect is flat; publish windows/ too
    if ((Split-Path -Leaf $t) -eq 'Claude-Connect' -and $f.Name -eq 'git-mode.ps1') {
      Copy-Item -Force $f.Src $dst
    } elseif ((Split-Path -Leaf $t) -eq 'Claude-Connect' -and $f.Name -eq 'editor-launch.ps1') {
      Copy-Item -Force $f.Src $dst
    } else {
      Copy-Item -Force $f.Src $dst
    }
    Write-Host ("  {0}" -f $f.Name)
  }
  # ensure connect.ps1 dotsources sidecar from same dir
  $cps = Get-Content (Join-Path $t 'connect.ps1') -Raw
  $verTxt = (Get-Content (Join-Path $t 'connect-version.txt') -Raw).Trim()
  $verPs1 = [regex]::Match($cps, "ConnectVersion = '([^']+)'").Groups[1].Value
  $hasSide = Test-Path (Join-Path $t 'cursor-proxy-sidecar.ps1')
  $hasBug = (Get-Content (Join-Path $t 'connect-update.ps1') -Raw) -match 'if \(\$script:UpdateEndpointTarget\)'
  Write-Host ("  ver_txt=$verTxt ver_ps1=$verPs1 sidecar=$hasSide update_bug=$hasBug")
}

# Smoke: run connect-update -Quiet should not crash
Write-Host '=== SMOKE update Quiet from Desktop ==='
$desk = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $desk 'connect-update.ps1') -ScriptDir $desk -Quiet
Write-Host ("update_exit=$LASTEXITCODE")
