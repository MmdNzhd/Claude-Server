$ErrorActionPreference = 'Continue'
$root = (Resolve-Path 'scripts/client').Path
$files = @(Get-ChildItem -LiteralPath $root -Recurse -File |
  Where-Object { $_.Extension -match '\.(ps1|sh|bat)$' })

function Count-Hits([string]$pattern) {
  $n = 0
  $samples = New-Object System.Collections.Generic.List[string]
  foreach ($f in $files) {
    $m = @(Select-String -LiteralPath $f.FullName -Pattern $pattern -ErrorAction SilentlyContinue)
    if ($m.Count -gt 0) {
      $n += $m.Count
      if ($samples.Count -lt 5) {
        foreach ($x in ($m | Select-Object -First 2)) {
          $samples.Add(("{0}:{1}" -f $f.Name, $x.LineNumber))
        }
      }
    }
  }
  return @{ N = $n; Sample = ($samples -join ', ') }
}

Write-Output '==== DUPLICATE / SHADOW FILES ===='
$pairs = @(
  @('connect-ui.ps1','windows\connect-ui.ps1'),
  @('connect-diagnostic.ps1','windows\connect-diagnostic.ps1'),
  @('connect-update.ps1','windows\connect-update.ps1')
)
foreach ($p in $pairs) {
  $a = Join-Path $root $p[0]; $b = Join-Path $root $p[1]
  $ha = if (Test-Path $a) { (Get-FileHash $a -Algorithm SHA256).Hash.Substring(0,12) } else { 'MISSING' }
  $hb = if (Test-Path $b) { (Get-FileHash $b -Algorithm SHA256).Hash.Substring(0,12) } else { 'MISSING' }
  $la = if (Test-Path $a) { (Get-Item $a).Length } else { 0 }
  $lb = if (Test-Path $b) { (Get-Item $b).Length } else { 0 }
  Write-Output ("{0} sha={1} len={2} | {3} sha={4} len={5} same={6}" -f $p[0],$ha,$la,$p[1],$hb,$lb,($ha -eq $hb))
}

Write-Output '==== DOTSOURCE / FILE REFS from connect.ps1 + bat + publish ===='
$anchors = @(
  (Join-Path $root 'windows\connect.ps1'),
  (Join-Path $root 'windows\connect.bat'),
  (Resolve-Path 'publish\publish.ps1').Path,
  (Join-Path $root 'windows\connect-bootstrap.ps1')
)
$atext = ''
foreach ($a in $anchors) { if (Test-Path $a) { $atext += "`n" + (Get-Content $a -Raw) } }
$candidates = @(
  'git-mode.ps1','connect-ui.ps1','windows\connect-ui.ps1','editor-launch.ps1',
  'cursor-auth-laptop.ps1','windows\connect-update.ps1','connect-update.ps1',
  'windows\cursor-proxy-sidecar.ps1','windows\windows-mcp-laptop.ps1',
  'windows\connect-heal.ps1','windows\connect-design.ps1','windows\connect-bootstrap.ps1',
  'windows\connect-diagnostic.ps1','connect-diagnostic.ps1','sync-desktop.ps1',
  'cursor-profile-db-tool.ps1','users\designer\connect.ps1'
)
foreach ($c in $candidates) {
  $name = Split-Path $c -Leaf
  $inAnchor = $atext -match [regex]::Escape($name)
  $h = Count-Hits ([regex]::Escape($name))
  Write-Output ("fileRefs={0,3} inConnectBatPublish={1}  {2}" -f $h.N, $inAnchor, $c)
}

Write-Output '==== KEY FUNCTION HIT COUNTS ===='
$funcs = @(
  'Get-TunnelBanner','Invalidate-TunnelBannerCache','Test-TunnelUp',
  'Acquire-FastTunnelPort','Acquire-TunnelPort','Ensure-BgTunnel','Sync-BgTunnel',
  'Get-CursorGoldenExportedAtStamp','Test-CursorAuthNeedsRefresh','Sync-CursorAuthFromServer',
  'Get-CursorMainPersonalProcesses','Get-RemoteEditorSessionPresence',
  'Initialize-NonElevatedLauncher','Start-ElevatedProcess','Start-ProcessElevatedDirect',
  'Invoke-SshXCore','Invoke-SshXChecked','Get-LfNormalizedShCopy',
  'Push-ServerConnectConf','Clear-SessionMount','Initialize-SessionBgTunnel',
  'Complete-PostTunnelRecovery','Invoke-RecoverIfNeeded','Remount-ProjectGit',
  'Invoke-ConnectSilentUpdateCheck','Invoke-ConnectBatRelaunch',
  'Repair-CursorComposerWorkspaceBindings','Heal-CursorProfileMachineIdFromLocal',
  'Get-ConnectProxyUrl','Initialize-ConnectProxyForSsh','Show-ConnectToast',
  'Connect-Design','Start-ConnectHeal','Invoke-ConnectDiagnostic',
  'Reap-Sidecar','Stop-CursorProxySidecar','Ensure-CursorProxySidecar',
  'Get-ForeignTunnelPortSet','Remove-ForeignTunnelPort','Save-ForeignTunnelPortSet',
  'Get-InteractiveLaptopUser','Sanitize-SshAliasConfig'
)
foreach ($fn in $funcs) {
  $h = Count-Hits ("\b$([regex]::Escape($fn))\b")
  Write-Output ("hits={0,3}  {1}  sample={2}" -f $h.N, $fn, $h.Sample)
}

Write-Output '==== git-mode function list (names only) ===='
Select-String -LiteralPath (Join-Path $root 'git-mode.ps1') -Pattern '^\s*function\s+([A-Za-z_][\w-]*)' |
  ForEach-Object { $_.Matches[0].Groups[1].Value }

Write-Output '==== SCRATCH _*.ps1 in tests ===='
Get-ChildItem (Join-Path $root 'tests') -Filter '_*.ps1' -EA SilentlyContinue |
  ForEach-Object { Write-Output ("{0} {1:N1}KB" -f $_.Name, ($_.Length/1KB)) }
