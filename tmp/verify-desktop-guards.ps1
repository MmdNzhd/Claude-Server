$ErrorActionPreference='Stop'
$desk = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
$ver = (Get-Content (Join-Path $desk 'connect-version.txt') -Raw).Trim()
$gm = Get-Content (Join-Path $desk 'git-mode.ps1') -Raw
$need = @(
  'Test-TunnelPortIsForeignPeer',
  'Get-TunnelHostKeyFingerprint',
  'PUSH_CONF blocked',
  'refuse_kill_foreign',
  'Test-TunnelPortAuthOwned',
  'ACQUIRE_SKIP: foreign_peer'
)
$fail=0
Write-Output "DESKTOP_VER=$ver"
foreach ($n in $need) {
  $ok = $gm.Contains($n)
  Write-Output ("GUARD {0}={1}" -f $n, $ok)
  if (-not $ok) { $fail++ }
}
$old = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260717\windows'
if (Test-Path (Join-Path $old 'connect-version.txt')) {
  $ov = (Get-Content (Join-Path $old 'connect-version.txt') -Raw).Trim()
  Write-Output "OLD_FOLDER_VER=$ov"
}
if ($ver -ne '20260721.4') { $fail++ }
exit $fail
