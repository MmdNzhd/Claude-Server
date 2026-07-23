$ErrorActionPreference = 'Continue'
$root = (Resolve-Path 'scripts/client').Path
Write-Output "ROOT=$root"

Write-Output '==== FILES by size ===='
Get-ChildItem -LiteralPath $root -Recurse -File |
  Where-Object { $_.Extension -match '\.(ps1|sh|bat)$' } |
  Sort-Object Length -Descending |
  Select-Object -First 35 |
  ForEach-Object {
    $rel = $_.FullName.Substring($root.Length).TrimStart('\','/')
    Write-Output ("{0,8:N1} KB  {1}" -f ($_.Length/1KB), $rel)
  }

# Collect function names from key files
$keyFiles = @(
  'git-mode.ps1','connect-ui.ps1','editor-launch.ps1','cursor-auth-laptop.ps1',
  'windows\connect.ps1','windows\connect.bat','connect-update.ps1',
  'cursor-proxy-sidecar.ps1','client-update-policy.json'
) | ForEach-Object { Join-Path $root $_ }

Write-Output '==== FUNCTION DEFS in core ps1 ===='
$defs = @{}
foreach ($f in @('git-mode.ps1','connect-ui.ps1','editor-launch.ps1','cursor-auth-laptop.ps1','windows\connect.ps1','connect-update.ps1','cursor-proxy-sidecar.ps1','cursor-auth-laptop.ps1')) {
  $path = Join-Path $root $f
  if (-not (Test-Path $path)) { Write-Output "MISSING $f"; continue }
  $i = 0
  Select-String -LiteralPath $path -Pattern '^\s*function\s+([A-Za-z_][\w-]*)' | ForEach-Object {
    $name = $_.Matches[0].Groups[1].Value
    $i++
    if (-not $defs.ContainsKey($name)) { $defs[$name] = @() }
    $defs[$name] += ("{0}:{1}" -f $f, $_.LineNumber)
  }
  Write-Output ("DEFS {0} count={1}" -f $f, $i)
}

Write-Output '==== CALL COUNTS (exclude def line approx) ===='
# Search whole scripts/client for each function name - sample suspicious / all git-mode heavy
$suspect = @(
  'Get-TunnelBanner','Test-TunnelBanner','Invoke-TunnelBanner','Get-RemoteTunnelBanner',
  'Acquire-FastTunnelPort','Acquire-TunnelPort','Ensure-Tunnel','Sync-Tunnel',
  'Test-GoldenStale','Get-AuthStamp','Sync-CursorAuthLaptop','Test-PersonalCursorDominant',
  'Start-ElevatedDirectFallback','Start-NonElevatedLauncher','Invoke-SshUserFix',
  'Clear-StaleRemoteUser','Test-ForeignRemoteUser','Reap-SidecarWatchdogs',
  'Start-SidecarWatchdog','Stop-SidecarWatchdog','Ensure-ProxySidecar',
  'Update-ExeOnly','Invoke-ExeOnlyUpdate','Show-UpdateUi',
  'Get-RemoteEditorSessionPresence','Test-RemoteEditorWindowOpen',
  'Complete-PostTunnelRecovery','RECOVERY_MOUNTOK','Invoke-MountProject'
)

# Broader: all defs with zero/low refs
$allNames = $defs.Keys | Sort-Object
$low = @()
foreach ($name in $allNames) {
  $hits = @(Select-String -Path (Join-Path $root '*') -Pattern ("\b{0}\b" -f [regex]::Escape($name)) -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -match '\.(ps1|sh|bat)$' })
  # also search tests
  $count = $hits.Count
  if ($count -le 2) {
    $low += [pscustomobject]@{ Name=$name; Hits=$count; Def=($defs[$name] -join ','); Sample=($hits | Select-Object -First 3 | ForEach-Object { ($_.Filename+':'+$_.LineNumber) }) -join '; ' }
  }
}

Write-Output '==== LOW HIT FUNCTIONS (<=2) ===='
$low | Sort-Object Hits, Name | ForEach-Object {
  Write-Output ("hits={0}  {1}  def={2}  sample={3}" -f $_.Hits, $_.Name, $_.Def, $_.Sample)
}

Write-Output '==== SUSPECT NAMED SEARCH ===='
foreach ($name in $suspect) {
  $hits = @(Select-String -Path (Join-Path $root '*') -Pattern ("\b{0}\b" -f [regex]::Escape($name)) -Recurse -EA SilentlyContinue |
    Where-Object { $_.Path -match '\.(ps1|sh|bat)$' })
  Write-Output ("hits={0,3}  {1}" -f $hits.Count, $name)
}

Write-Output '==== ORPHAN CANDIDATE FILES (not mentioned in connect.ps1/bat/publish) ===='
$anchors = @()
foreach ($a in @('windows\connect.ps1','windows\connect.bat','..\publish\publish.ps1','connect-update.ps1')) {
  $p = Join-Path $root $a
  if ($a.StartsWith('..')) { $p = Join-Path (Resolve-Path 'scripts').Path ($a.Substring(3)) }
  if (Test-Path $p) { $anchors += Get-Content -LiteralPath $p -Raw }
}
$anchorText = ($anchors -join "`n")
Get-ChildItem -LiteralPath $root -Recurse -File |
  Where-Object { $_.Extension -match '\.(ps1|sh|bat)$' -and $_.Name -notmatch '^_' } |
  ForEach-Object {
    $rel = $_.Name
    $fullRel = $_.FullName.Substring($root.Length).TrimStart('\')
    # skip windows/connect itself
    if ($fullRel -match '^(windows\\connect\.(ps1|bat)|mac\\connect\.sh)$') { return }
    $mentioned = ($anchorText -match [regex]::Escape($_.Name)) -or ($anchorText -match [regex]::Escape($fullRel.Replace('\','/')))
    # also check if any other file dotsources it
    $dot = @(Select-String -Path (Join-Path $root '*') -Pattern ([regex]::Escape($_.Name)) -Recurse -EA SilentlyContinue |
      Where-Object { $_.Path -ne $_.Path -or $_.Filename -ne $_.Name })
    $refCount = @(Select-String -Path (Join-Path $root '*') -Pattern ([regex]::Escape($_.Name)) -Recurse -EA SilentlyContinue |
      Where-Object { $_.Path -match '\.(ps1|sh|bat|md|json)$' -and $_.Filename -ne $_.Name }).Count
    if ($refCount -le 1) {
      Write-Output ("orphan? refs={0}  {1}" -f $refCount, $fullRel)
    }
  }

Write-Output '==== AGENT SCRATCH under tests ===='
Get-ChildItem (Join-Path $root 'tests') -File -Filter '_*.ps1' -EA SilentlyContinue |
  ForEach-Object { Write-Output ("scratch {0} KB={1:N1}" -f $_.Name, ($_.Length/1KB)) }

Write-Output '==== DONE ===='
