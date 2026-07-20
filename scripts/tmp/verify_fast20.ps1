$ErrorActionPreference='Stop'
$errs=$null; $null=$null
foreach ($f in @(
  'scripts\client\windows\connect.ps1',
  'scripts\client\git-mode.ps1',
  'scripts\client\connect-ui.ps1'
)) {
  $e=$null; $t=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $f), [ref]$t, [ref]$e)
  if ($e -and $e.Count -gt 0) {
    Write-Host ("PARSE_FAIL " + $f)
    $e | Select-Object -First 8 | ForEach-Object { Write-Host $_.ToString() }
    throw "parse fail $f"
  }
  Write-Host ("parse_ok " + $f)
}

. .\scripts\client\connect-ui.ps1
. .\scripts\client\git-mode.ps1
# connect.ps1 is huge / has side effects - just check functions exist via select-string
if (-not (Select-String -Path scripts\client\windows\connect.ps1 -Pattern 'function Get-ConnectSshMuxPath' -Quiet)) { throw 'mux helper missing' }
if (-not (Select-String -Path scripts\client\windows\connect.ps1 -Pattern 'ControlMaster=auto' -Quiet)) { throw 'ControlMaster missing' }
if (-not (Select-String -Path scripts\client\git-mode.ps1 -Pattern 'Speed \(stable\): preserve\+write\+self-heal' -Quiet)) { throw 'push batch missing' }
if (-not (Select-String -Path scripts\client\git-mode.ps1 -Pattern 'one SSH reads conf' -Quiet)) { throw 'warn batch missing' }
# update untouched
if (-not (Select-String -Path scripts\client\windows\connect-update.ps1 -Pattern 'attempt -le 3' -Quiet)) { throw 'update retry3 missing' }
if (Select-String -Path scripts\client\windows\connect-update.ps1 -Pattern 'TimeoutMs 8000 -RequireStdout' -Quiet) { throw 'update timeout wrongly shortened' }

$ver=(Get-Content scripts\client\windows\connect-version.txt -Raw).Trim()
$cv=([regex]::Match((Get-Content scripts\client\windows\connect.ps1 -Raw), "ConnectVersion = '([^']+)'")).Groups[1].Value
Write-Host "ver=$ver cv=$cv"
if ($ver -ne '20260719.20' -or $cv -ne $ver) { throw 'ver mismatch' }

# Live mux RTT compare (does not change server)
$Alias='claude-server-sepidz'
$mux = "\\.\pipe\claude-connect-test-%C"
function Rtt([string[]]$extra) {
  $sw=[Diagnostics.Stopwatch]::StartNew()
  $p=Start-Process ssh -ArgumentList (@('-n','-o','BatchMode=yes','-o','ConnectTimeout=10','-o','ClearAllForwardings=yes') + $extra + @($Alias,'echo ok')) -NoNewWindow -PassThru -RedirectStandardOutput ($env:TEMP+'\m.out') -RedirectStandardError ($env:TEMP+'\m.err')
  if (-not $p.WaitForExit(20000)) { try{$p.Kill()}catch{}; return -1 }
  $sw.Stop(); return [int]$sw.ElapsedMilliseconds
}
$cold = Rtt @('-o','ControlMaster=no')
$m1 = Rtt @('-o','ControlMaster=auto',"-o","ControlPath=$mux",'-o','ControlPersist=60')
$m2 = Rtt @('-o','ControlMaster=auto',"-o","ControlPath=$mux",'-o','ControlPersist=60')
& ssh -O exit -o ControlPath=$mux $Alias 2>$null | Out-Null
Write-Host ("rtt_cold_no_mux_ms=$cold mux_first=$m1 mux_second=$m2")
Write-Host 'VERIFY_OK'
