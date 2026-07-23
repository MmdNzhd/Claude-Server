$ErrorActionPreference = 'Continue'
$root = (Resolve-Path 'scripts/client').Path
$files = @(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Extension -match '\.(ps1|sh|bat)$' -and $_.Name -notmatch '^_dead_code' })
function Hits($pat) {
  $n=0; foreach ($f in $files) { $n += @(Select-String -LiteralPath $f.FullName -Pattern $pat -EA SilentlyContinue).Count }; $n
}
# Real git-mode names: count calls excluding definition file line roughly
$names = @(
  'Clear-TunnelBannerCache','Get-TunnelBanner','Ensure-SessionTunnel','Sync-SessionTunnelProcess',
  'Try-ReattachSessionTunnelProcess','Wait-ForTunnelUp','Stop-SessionTunnelCleanup',
  'Complete-CursorProxyAfterTunnel','Ensure-CursorProxySidecar','Claim-CursorProxyOwner',
  'Test-TunnelNeedsProxyReseed','Add-TunnelHttpProxyLeg','Clear-LegacyDynamicSocksTunnels',
  'Warn-ForeignServerSession','Test-IsPrimaryTunnelPublisher','Add-ClearedTunnelPort',
  'Test-RecentlyClearedTunnelPort','Push-LaptopExecBundleIfChanged','Push-ClaudeServerScripts',
  'Configure-GitMode','Show-MountGitWarn','Unmount-OtherProjects'
)
Write-Output '==== LIVE git-mode funcs ===='
foreach ($n in $names) {
  Write-Output ("hits={0,3}  {1}" -f (Hits "\b$([regex]::Escape($n))\b"), $n)
}

# Sidecar exports
Write-Output '==== sidecar function defs ===='
$side = Join-Path $root 'windows\cursor-proxy-sidecar.ps1'
Select-String -LiteralPath $side -Pattern '^\s*function\s+' | ForEach-Object { $_.Line.Trim() }

# heal / diagnostic entry
Write-Output '==== heal/diagnostic entrypoints ===='
Select-String -LiteralPath (Join-Path $root 'windows\connect-heal.ps1') -Pattern '^\s*function\s+|^param\(' | Select-Object -First 15 | ForEach-Object { $_.Line.Trim() }
Select-String -LiteralPath (Join-Path $root 'connect-diagnostic.ps1') -Pattern '^\s*function\s+' | Select-Object -First 20 | ForEach-Object { $_.Line.Trim() }

# Auth real names
Write-Output '==== auth function defs ===='
Select-String -LiteralPath (Join-Path $root 'cursor-auth-laptop.ps1') -Pattern '^\s*function\s+' | ForEach-Object { $_.Line.Trim() }

# Stale windows\connect-ui who references path windows\connect-ui
Write-Output '==== refs to windows\\connect-ui.ps1 path ===='
Write-Output ("pathRefs=" + (Hits 'windows[/\\]connect-ui\.ps1'))
Write-Output ("DotSourceSibling connect-ui only by name; publish Src=scripts\\client\\connect-ui.ps1")

# Count agent scratch
$scratch = @(Get-ChildItem (Join-Path $root 'tests') -Filter '_*.ps1' | Where-Object { $_.Name -ne '_paths.ps1' })
Write-Output ("scratch_tests_underscore_ps1={0} (keep _paths.ps1)" -f $scratch.Count)
