$ErrorActionPreference = 'Continue'
$batDir = 'C:\Users\Smart\Downloads\claude-code-client-20260715\windows'
$bat = Join-Path $batDir 'connect.bat'
$logDir = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
$day = Get-Date -Format 'yyyyMMdd'
$log = Join-Path $logDir ("connect-{0}.log" -f $day)

function Test-Pe([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return @{ Ok=$false; Why='missing' } }
  try {
    $fs = [IO.File]::OpenRead($Path)
    try {
      $h = New-Object byte[] 64
      if ($fs.Read($h,0,64) -lt 64) { return @{ Ok=$false; Why='short' } }
      if ($h[0] -ne 0x4D -or $h[1] -ne 0x5A) { return @{ Ok=$false; Why='noMZ' } }
      $off = [BitConverter]::ToInt32($h, 0x3C)
      $null = $fs.Seek([int64]$off, [IO.SeekOrigin]::Begin)
      $s = New-Object byte[] 4
      if ($fs.Read($s,0,4) -ne 4) { return @{ Ok=$false; Why='nosig' } }
      $ok = ($s[0]-eq 0x50 -and $s[1]-eq 0x45 -and $s[2]-eq 0 -and $s[3]-eq 0)
      $len = (Get-Item -LiteralPath $Path).Length
      return @{ Ok=$ok; Why=($(if($ok){'PE'}else{'badPE'})); Len=$len }
    } finally { $fs.Dispose() }
  } catch { return @{ Ok=$false; Why=$_.Exception.Message } }
}

Write-Host '=== BEFORE ==='
Write-Host ("bat exists={0}" -f (Test-Path $bat))
Get-ChildItem -LiteralPath $batDir -ErrorAction SilentlyContinue | ForEach-Object {
  '{0,-40} {1,12}' -f $_.Name, $_.Length
}
$exeHere = Join-Path $batDir 'Claude-Connect.exe'
$pe0 = Test-Pe $exeHere
Write-Host ("exe_here pe={0} why={1} len={2}" -f $pe0.Ok, $pe0.Why, $pe0.Len)

# Kill stuck connect UIs from prior tests (keep tunnel ssh alone)
Write-Host '=== kill prior connect-boot ==='
Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
  $cl = [string]$_.CommandLine
  $cl -match 'connect-boot\.ps1' -or $cl -match 'Claude-Connect\\connect\.ps1' -or ($cl -match 'connect\.bat' -and $cl -match 'claude-code-client')
} | ForEach-Object {
  Write-Host (" kill pid={0}" -f $_.ProcessId)
  Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2

$mark = Get-Date
Write-Host ("=== LAUNCH bat at {0} ===" -f $mark.ToString('HH:mm:ss'))
$p = Start-Process -FilePath $bat -WorkingDirectory $batDir -PassThru -WindowStyle Normal
Write-Host ("started pid={0}" -f $p.Id)

# Poll logs for bootstrap/update outcome up to ~90s
$deadline = (Get-Date).AddSeconds(90)
$saw = @{ bootstrap=$false; update=$false; exe_only=$false; pe_invalid=$false; up_to_date=$false; fail=$false; redirect=$false; cleaned=$false }
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 3
  if (Test-Path $log) {
    $tail = Get-Content $log -Tail 80 -ErrorAction SilentlyContinue
    foreach ($line in $tail) {
      if ($line -notmatch $mark.ToString('yyyy-MM-dd')) { continue }
      # accept lines after mark time roughly via string compare on HH
      if ($line -match 'BOOTSTRAP') { $saw.bootstrap = $true }
      if ($line -match 'UPDATE:') { $saw.update = $true }
      if ($line -match 'exe_only') { $saw.exe_only = $true }
      if ($line -match 'pe_invalid|not a valid|corrupt') { $saw.pe_invalid = $true }
      if ($line -match 'up_to_date|applied_ok') { $saw.up_to_date = $true }
      if ($line -match '\[ERROR\].*FAIL|UPDATE_UNHANDLED') { $saw.fail = $true }
      if ($line -match 'redirect|legacy_cleaned|healed canon') { $saw.redirect = $true; if ($line -match 'legacy_cleaned') { $saw.cleaned = $true } }
    }
  }
  # success-ish: redirected or up_to_date after bootstrap
  if ($saw.bootstrap -and ($saw.up_to_date -or $saw.redirect -or $saw.exe_only)) { break }
}

Write-Host '=== SAW ==='
$saw.GetEnumerator() | ForEach-Object { Write-Host (" {0}={1}" -f $_.Key, $_.Value) }

Write-Host '=== LOG TAIL (last 40 matching) ==='
if (Test-Path $log) {
  Get-Content $log -Tail 120 | Where-Object {
    $_ -match 'BOOTSTRAP|UPDATE:|exe_only|pe_|FAIL|legacy|redirect|up_to_date|applied|healed|cleaned'
  } | Select-Object -Last 40
}

Write-Host '=== AFTER folder ==='
Get-ChildItem -LiteralPath $batDir -ErrorAction SilentlyContinue | ForEach-Object {
  '{0,-40} {1,12}' -f $_.Name, $_.Length
}
$pe1 = Test-Pe $exeHere
Write-Host ("exe_here pe={0} why={1} len={2}" -f $pe1.Ok, $pe1.Why, $pe1.Len)

$desk = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect.exe'
$canon = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect\Claude-Connect.exe'
$peD = Test-Pe $desk
$peC = Test-Pe $canon
Write-Host ("desk_exe pe={0} len={1}" -f $peD.Ok, $peD.Len)
Write-Host ("canon_exe pe={0} len={1}" -f $peC.Ok, $peC.Len)

# If broken: re-fetch EXE from server into this folder and verify
if (-not $pe1.Ok) {
  Write-Host '=== REFETCH EXE (broken) ==='
  $cfg = Join-Path $env:USERPROFILE '.config\claude-connect\connect.conf'
  $ru = 'smart'; $ip = '192.168.210.240'
  if (Test-Path $cfg) {
    Get-Content $cfg | ForEach-Object {
      if ($_ -match '^REMOTE_USER=(.+)$') { $ru = $Matches[1].Trim() }
    }
  }
  $tmp = Join-Path $env:TEMP 'claude-connect-refetch.exe'
  $target = "{0}@{1}" -f $ru, $ip
  $scp = Start-Process -FilePath 'scp' -ArgumentList @(
    '-o','BatchMode=yes','-o','ConnectTimeout=20','-o','ControlMaster=no','-q',
    ($target + ':/usr/local/share/claude-client/Claude-Connect.exe'), $tmp
  ) -Wait -PassThru -NoNewWindow
  Write-Host ("scp exit={0}" -f $scp.ExitCode)
  $peT = Test-Pe $tmp
  Write-Host ("tmp pe={0} len={1}" -f $peT.Ok, $peT.Len)
  if ($peT.Ok) {
    Copy-Item -LiteralPath $tmp -Destination $exeHere -Force
    Copy-Item -LiteralPath $tmp -Destination $desk -Force
    Copy-Item -LiteralPath $tmp -Destination $canon -Force
    Write-Host 'refetch copied to here+desk+canon'
  } else {
    Write-Host 'REFETCH STILL BAD'
  }
  $pe2 = Test-Pe $exeHere
  Write-Host ("exe_here after refetch pe={0} len={1}" -f $pe2.Ok, $pe2.Len)
}

Write-Host '=== DONE ==='
