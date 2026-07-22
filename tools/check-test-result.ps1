$ErrorActionPreference='Continue'
function Test-Pe([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return 'missing' }
  try {
    $fs=[IO.File]::OpenRead($Path)
    try {
      $h=New-Object byte[] 64
      if ($fs.Read($h,0,64) -lt 64) { return 'short' }
      if ($h[0] -ne 0x4D -or $h[1] -ne 0x5A) { return 'noMZ' }
      $off=[BitConverter]::ToInt32($h,0x3C)
      $null=$fs.Seek([int64]$off,[IO.SeekOrigin]::Begin)
      $s=New-Object byte[] 4
      if ($fs.Read($s,0,4) -ne 4) { return 'nosig' }
      $len=(Get-Item $Path).Length
      if ($s[0]-eq 0x50 -and $s[1]-eq 0x45 -and $s[2]-eq 0 -and $s[3]-eq 0) { return "OK len=$len" }
      return "BAD_PE len=$len"
    } finally { $fs.Dispose() }
  } catch { return $_.Exception.Message }
}

$batDir='C:\Users\Smart\Downloads\claude-code-client-20260715\windows'
Write-Host '=== folder ==='
if (Test-Path $batDir) {
  Get-ChildItem $batDir | ForEach-Object { '{0,-40} {1,12}' -f $_.Name, $_.Length }
} else { Write-Host 'MISSING folder' }

Write-Host ''
Write-Host '=== PE checks ==='
@(
  (Join-Path $batDir 'Claude-Connect.exe'),
  (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect.exe'),
  (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect\Claude-Connect.exe')
) | ForEach-Object { Write-Host ("{0} -> {1}" -f $_, (Test-Pe $_)) }

Write-Host ''
Write-Host '=== log tail ==='
$log = Join-Path $env:USERPROFILE ('.config\claude-connect\logs\connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))
Write-Host ("log={0}" -f $log)
if (Test-Path $log) {
  Get-Content $log -Tail 80 | Where-Object {
    $_ -match 'BOOTSTRAP|UPDATE:|exe_only|pe_|FAIL|legacy|redirect|up_to_date|applied|healed|cleaned|20260722'
  } | Select-Object -Last 50
}

Write-Host ''
Write-Host '=== connect processes ==='
Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
  $cl=[string]$_.CommandLine
  $cl -match 'connect-boot\.ps1' -or $cl -match 'Claude-Connect\\connect\.ps1'
} | ForEach-Object {
  $c=[string]$_.CommandLine
  if ($c.Length -gt 140) { $c=$c.Substring(0,140)+'...' }
  Write-Host ("pid={0} {1}" -f $_.ProcessId, $c)
}
