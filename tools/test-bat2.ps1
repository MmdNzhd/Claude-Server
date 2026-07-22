$ErrorActionPreference='Continue'
$batDir='C:\Users\Smart\Downloads\claude-code-client-20260715\windows'
$bat=Join-Path $batDir 'connect.bat'
$log=Join-Path $env:USERPROFILE ('.config\claude-connect\logs\connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))
$runId = ('test{0}' -f (Get-Date -Format 'HHmmss'))
$env:CLAUDE_CONNECT_RUN_ID = $runId

function Test-Pe([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return 'missing' }
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
    if ($s[0]-eq 0x50 -and $s[1]-eq 0x45 -and $s[2]-eq 0 -and $s[3]-eq 0) { return "OK:$len" }
    return "BAD:$len"
  } finally { $fs.Dispose() }
}

function Refetch-Exe([string]$Dest) {
  Write-Host 'REFETCH from server...'
  $tmp = Join-Path $env:TEMP 'claude-refetch.exe'
  $p = Start-Process scp -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=20','-o','ControlMaster=no','-q','smart@192.168.210.240:/usr/local/share/claude-client/Claude-Connect.exe',$tmp) -Wait -PassThru -NoNewWindow
  Write-Host ("scp exit={0}" -f $p.ExitCode)
  $r = Test-Pe $tmp
  Write-Host ("tmp={0}" -f $r)
  if ($r -notlike 'OK:*') { throw "refetch bad: $r" }
  $null = New-Item -ItemType Directory -Force -Path (Split-Path $Dest) 
  Copy-Item $tmp $Dest -Force
  Copy-Item $tmp (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect.exe') -Force
  Copy-Item $tmp (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect\Claude-Connect.exe') -Force
  Write-Host ("placed {0}" -f (Test-Pe $Dest))
}

Write-Host ("RUN_ID={0}" -f $runId)
Write-Host 'BEFORE folder files:'
(Get-ChildItem $batDir -Name) -join ', ' | Write-Host
Write-Host ("exe_here={0}" -f (Test-Pe (Join-Path $batDir 'Claude-Connect.exe')))

# offset before launch
$beforeLen = 0
if (Test-Path $log) { $beforeLen = (Get-Item $log).Length }

$proc = Start-Process -FilePath $bat -WorkingDirectory $batDir -PassThru -WindowStyle Minimized
Write-Host ("launched pid={0}" -f $proc.Id)

$ok=$false; $fail=$false; $lines=@()
for ($i=0; $i -lt 36; $i++) {
  Start-Sleep -Seconds 3
  if (-not (Test-Path $log)) { continue }
  # read new bytes roughly via Get-Content tail filtered by run id
  $chunk = Get-Content $log -Tail 100 -EA SilentlyContinue | Where-Object { $_ -match $runId -or $_ -match 'BOOTSTRAP|UPDATE:|legacy|redirect|healed|cleaned|exe_only|pe_' }
  # also catch lines without run id from child if id not propagated
  $recent = Get-Content $log -Tail 30 -EA SilentlyContinue
  $lines = @($recent)
  $text = ($recent -join "`n")
  if ($text -match 'up_to_date|applied_ok|legacy_cleaned|healed canon|redirect legacy') { $ok=$true; break }
  if ($text -match 'FAIL UPDATE|UPDATE_UNHANDLED|pe_invalid|exe_only_pe_invalid') { $fail=$true; break }
  # redirected to canon often changes run continuation
  if ($text -match 'BOOTSTRAP: connect.bat start here=.*Desktop\\Claude-Connect' -and $text -match 'up_to_date|skip canon') { $ok=$true; break }
}

Write-Host '=== recent log ==='
$lines | Where-Object { $_ -match 'BOOTSTRAP|UPDATE:|legacy|redirect|healed|cleaned|exe_only|pe_|FAIL|up_to_date|applied' } | Select-Object -Last 35 | ForEach-Object { $_ }

Write-Host '=== AFTER folder ==='
Get-ChildItem $batDir | ForEach-Object { '{0,-40} {1,12}' -f $_.Name, $_.Length }
$exe = Join-Path $batDir 'Claude-Connect.exe'
$pe = Test-Pe $exe
Write-Host ("exe_here={0}" -f $pe)
Write-Host ("desk={0}" -f (Test-Pe (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect.exe')))
Write-Host ("canon={0}" -f (Test-Pe (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect\Claude-Connect.exe')))

if ($pe -like 'BAD:*' -or $pe -eq 'missing') {
  Write-Host 'BROKEN -> refetch'
  Refetch-Exe $exe
  Write-Host ("final exe_here={0}" -f (Test-Pe $exe))
} elseif ($ok) {
  Write-Host 'RESULT=OK'
} elseif ($fail) {
  Write-Host 'RESULT=FAIL_IN_LOG'
  Refetch-Exe $exe
} else {
  Write-Host 'RESULT=TIMEOUT_OR_PARTIAL'
  # still ensure exe present+valid for this folder if legacy clean expected
  if ($pe -ne 'missing' -and $pe -notlike 'OK:*') { Refetch-Exe $exe }
}

# show if connect UI alive
$alive = @(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object { ([string]$_.CommandLine) -match 'connect-boot\.ps1' })
Write-Host ("connect_boot_count={0}" -f $alive.Count)
