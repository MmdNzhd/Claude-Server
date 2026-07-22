$day = Get-Date -Format 'yyyyMMdd'
$base = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
$log = Join-Path $base ("connect-{0}.log" -f $day)
$wm = $log + '.sync-offset'
$pend = $log + '.sync-pending'
Write-Host ("USERPROFILE=" + $env:USERPROFILE)
Write-Host ("USERNAME=" + $env:USERNAME)
Write-Host ("log=" + $log)
Write-Host ("log_exists=" + (Test-Path -LiteralPath $log))
if (Test-Path -LiteralPath $log) { Write-Host ("log_len=" + (Get-Item -LiteralPath $log).Length) }
Write-Host ("wm=" + $wm)
Write-Host ("wm_exists=" + (Test-Path -LiteralPath $wm))
if (Test-Path -LiteralPath $wm) {
  $bytes = [IO.File]::ReadAllBytes($wm)
  Write-Host ("wm_bytes_hex=" + ([BitConverter]::ToString($bytes)))
  Write-Host ("wm_raw=[" + [Text.Encoding]::ASCII.GetString($bytes) + "]")
  Write-Host ("wm_len=" + $bytes.Length)
} else {
  Write-Host 'wm_MISSING'
}
Write-Host ("pend_exists=" + (Test-Path -LiteralPath $pend))
if (Test-Path -LiteralPath $pend) { Write-Host ("pend=[" + ([IO.File]::ReadAllText($pend)) + "]") }
# Also list all sync-offset files
Write-Host '--- all *.sync-offset in log dir ---'
if (Test-Path $base) {
  Get-ChildItem -LiteralPath $base -Filter '*.sync-offset' -ErrorAction SilentlyContinue |
    ForEach-Object { Write-Host ("{0} len={1} mtime={2} content=[{3}]" -f $_.FullName, $_.Length, $_.LastWriteTime, ([IO.File]::ReadAllText($_.FullName))) }
}
# VirtualStore
$vsRoots = @(
  (Join-Path $env:LOCALAPPDATA 'VirtualStore\Users\Smart\.config\claude-connect\logs'),
  (Join-Path $env:LOCALAPPDATA 'VirtualStore\Users\smart\.config\claude-connect\logs')
)
foreach ($vs in $vsRoots) {
  Write-Host ("VS_check=" + $vs + " exists=" + (Test-Path $vs))
  if (Test-Path $vs) {
    Get-ChildItem $vs -ErrorAction SilentlyContinue | ForEach-Object {
      Write-Host ("  VS:{0} len={1}" -f $_.Name, $_.Length)
    }
  }
}
# Elevated vs not: whoami /groups for Admin
Write-Host '--- integrity/elevation ---'
try { Write-Host ((whoami /groups) | Select-String 'High Mandatory|Medium Mandatory|S-1-16') } catch {}
