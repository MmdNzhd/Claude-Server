$ErrorActionPreference='Continue'
$batDir='C:\Users\Smart\Downloads\claude-code-client-20260715\windows'
$desk=Join-Path $env:USERPROFILE 'Desktop\Claude-Connect.exe'
$canon=Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'

function Test-Pe([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return 'missing' }
  try {
    $fs=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
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
      return "BAD_PE:$len"
    } finally { $fs.Dispose() }
  } catch { return ("ERR:" + $_.Exception.Message) }
}

Write-Host '=== kill lockers ==='
Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
  $cl=[string]$_.CommandLine
  $cl -match 'connect-boot|Claude-Connect\.exe|claude-code-client-20260715|setup-launch|stress-connect'
} | ForEach-Object {
  Write-Host ("kill {0}" -f $_.ProcessId)
  Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue
}
Start-Sleep -Seconds 2

Write-Host '=== BEFORE ==='
if (Test-Path $batDir) {
  Get-ChildItem $batDir -Force | ForEach-Object { '{0,-40} {1,12}' -f $_.Name, $_.Length }
} else { Write-Host 'folder missing' }

Write-Host ("here_exe " + (Test-Pe (Join-Path $batDir 'Claude-Connect.exe')))
Write-Host ("desk_exe " + (Test-Pe $desk))
Write-Host ("canon_exe " + (Test-Pe (Join-Path $canon 'Claude-Connect.exe')))

# Fetch good EXE from server
$tmp=Join-Path $env:TEMP 'claude-good.exe'
Remove-Item $tmp -Force -EA SilentlyContinue
$scp=Start-Process scp -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=20','-o','ControlMaster=no','-q','smart@192.168.210.240:/usr/local/share/claude-client/Claude-Connect.exe',$tmp) -Wait -PassThru -NoNewWindow
Write-Host ("scp_exit={0} tmp={1}" -f $scp.ExitCode, (Test-Pe $tmp))
if ((Test-Pe $tmp) -notlike 'OK:*') { throw 'server exe bad' }

# CLEAN folder to EXE + README only
Write-Host '=== CLEAN folder ==='
Get-ChildItem $batDir -Force -EA SilentlyContinue | ForEach-Object {
  if ($_.Name -in @('Claude-Connect.exe','READ-ME.txt')) { return }
  try {
    Remove-Item $_.FullName -Recurse -Force -ErrorAction Stop
    Write-Host ("removed {0}" -f $_.Name)
  } catch {
    Write-Host ("LOCK remove fail {0}: {1}" -f $_.Name, $_.Exception.Message)
    # rename aside
    try {
      $bak = $_.FullName + '.OLDDEAD'
      Move-Item $_.FullName $bak -Force
      Write-Host ("renamed {0}" -f $_.Name)
    } catch { Write-Host ("rename fail {0}" -f $_.Name) }
  }
}

# Place good EXE
Copy-Item $tmp (Join-Path $batDir 'Claude-Connect.exe') -Force
Copy-Item $tmp $desk -Force
if (-not (Test-Path $canon)) { New-Item -ItemType Directory -Force -Path $canon | Out-Null }
Copy-Item $tmp (Join-Path $canon 'Claude-Connect.exe') -Force

@'
Claude Connect
==============
This old Downloads folder is cleaned.

Double-click: Claude-Connect.exe

Or use: Desktop\Claude-Connect.exe
'@ | Set-Content (Join-Path $batDir 'READ-ME.txt') -Encoding UTF8

Write-Host '=== AFTER folder ==='
Get-ChildItem $batDir -Force | ForEach-Object { '{0,-40} {1,12}' -f $_.Name, $_.Length }
Write-Host ("here_exe " + (Test-Pe (Join-Path $batDir 'Claude-Connect.exe')))

# Actually RUN the EXE (files-only then launch)
Write-Host '=== RUN EXE ==='
$exe=Join-Path $batDir 'Claude-Connect.exe'
$p=Start-Process -FilePath $exe -WorkingDirectory $batDir -PassThru
Write-Host ("started pid={0}" -f $p.Id)
Start-Sleep -Seconds 10
$alive=@(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
  ([string]$_.CommandLine) -match 'Claude-Connect\\connect-boot\.ps1' -or ([string]$_.CommandLine) -match 'Desktop\\Claude-Connect\\connect\.ps1'
})
Write-Host ("connect_ui_count={0}" -f $alive.Count)
if ($alive.Count -gt 0) {
  Write-Host 'RUN_OK connect UI is up'
} else {
  # try direct canon bat
  Write-Host 'EXE may have installed without UI; try canon bat'
  $cbat=Join-Path $canon 'connect.bat'
  if (Test-Path $cbat) {
    $p2=Start-Process -FilePath $cbat -WorkingDirectory $canon -PassThru -WindowStyle Normal
    Write-Host ("canon_bat pid={0}" -f $p2.Id)
    Start-Sleep -Seconds 8
    $alive2=@(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
      ([string]$_.CommandLine) -match 'connect-boot\.ps1'
    })
    Write-Host ("connect_ui_count2={0}" -f $alive2.Count)
  } else {
    Write-Host 'canon bat missing - setup failed'
  }
}

# setup log
$slog=Join-Path $env:TEMP 'claude-connect-setup.log'
if (Test-Path $slog) {
  Write-Host '=== setup log tail ==='
  Get-Content $slog -Tail 20
}
