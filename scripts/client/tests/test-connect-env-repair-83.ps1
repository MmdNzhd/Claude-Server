# test-connect-env-repair-83.ps1 - DOS 8.3 USERPROFILE/TEMP repair (Parsa / p.beheshti)
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not (Test-Path (Join-Path $RepoRoot 'scripts\client\windows\connect-env-repair.ps1'))) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
}
. (Join-Path $PSScriptRoot '_paths.ps1') -ErrorAction SilentlyContinue

$pass = 0; $fail = 0
function Assert([bool]$cond, [string]$msg) {
    if ($cond) { $script:pass++; Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { $script:fail++; Write-Host "  FAIL  $msg" -ForegroundColor Red }
}

$repairPath = Join-Path $RepoRoot 'scripts\client\windows\connect-env-repair.ps1'
$updPath = Join-Path $RepoRoot 'scripts\client\windows\connect-update.ps1'
$ps1Path = Join-Path $RepoRoot 'scripts\client\windows\connect.ps1'
$batPath = Join-Path $RepoRoot 'scripts\client\windows\connect.bat'
$manifest = Join-Path $RepoRoot 'publish\client-bundle-manifest.tsv'

Assert (Test-Path -LiteralPath $repairPath) 'connect-env-repair.ps1 exists'
Assert ((Get-Content $updPath -Raw) -match 'connect-env-repair') 'connect-update.ps1 references connect-env-repair'
Assert ((Get-Content $ps1Path -Raw) -match 'connect-env-repair') 'connect.ps1 references connect-env-repair'
Assert ((Get-Content $batPath -Raw) -match 'connect-env-repair\.ps1') 'connect.bat invokes connect-env-repair'
Assert ((Get-Content $manifest -Raw) -match 'connect-env-repair\.ps1') 'manifest ships connect-env-repair.ps1'
Assert ((Get-Content $repairPath -Raw) -match "\-notmatch '~'") 'repair rejects 8.3 tilde paths'

# Live simulation: poison env with fake 8.3 profile, then repair.
$realProfile = [Environment]::GetFolderPath('UserProfile')
$realTemp = $env:TEMP
$realTmp = $env:TMP
$realLocal = $env:LOCALAPPDATA
$realUserProfile = $env:USERPROFILE
try {
    $fakeShort = 'C:\Users\PAAA7~1.BEH'
    $env:USERPROFILE = $fakeShort
    $env:LOCALAPPDATA = Join-Path $fakeShort 'AppData\Local'
    $env:TEMP = Join-Path $fakeShort 'AppData\Local\Temp'
    $env:TMP = $env:TEMP

    $job = Start-Job -ScriptBlock {
        param($RepairPath, $FakeShort)
        $env:USERPROFILE = $FakeShort
        $env:LOCALAPPDATA = Join-Path $FakeShort 'AppData\Local'
        $env:TEMP = Join-Path $FakeShort 'AppData\Local\Temp'
        $env:TMP = $env:TEMP
        . $RepairPath
        [pscustomobject]@{
            UserProfile = $env:USERPROFILE
            Temp = $env:TEMP
            Local = $env:LOCALAPPDATA
        }
    } -ArgumentList $repairPath, $fakeShort
    $r = Wait-Job $job -Timeout 30 | Receive-Job
    Remove-Job $job -Force -ErrorAction SilentlyContinue

    Assert ($null -ne $r) 'repair job returned result'
    if ($r) {
        Assert ($r.UserProfile -notmatch '~') ("USERPROFILE repaired (no tilde): {0}" -f $r.UserProfile)
        Assert ($r.Temp -notmatch '~') ("TEMP repaired (no tilde): {0}" -f $r.Temp)
        Assert (Test-Path -LiteralPath $r.Temp) 'repaired TEMP exists'
        $probe = Join-Path $r.Temp ("claude-83-probe-{0}" -f $PID)
        New-Item -ItemType Directory -Force -Path $probe -ErrorAction Stop | Out-Null
        Assert (Test-Path -LiteralPath $probe) 'New-Item under repaired TEMP works'
        Remove-Item -LiteralPath $probe -Recurse -Force -ErrorAction SilentlyContinue
    }
} finally {
    $env:USERPROFILE = $realUserProfile
    $env:LOCALAPPDATA = $realLocal
    $env:TEMP = $realTemp
    $env:TMP = $realTmp
}

# EmitBatEnv contract
$emit = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $repairPath -EmitBatEnv)
$emitText = ($emit | Out-String)
Assert ([bool]($emitText -match '(?m)^USERPROFILE=')) 'EmitBatEnv prints USERPROFILE='
Assert ([bool]($emitText -match '(?m)^TEMP=')) 'EmitBatEnv prints TEMP='
Assert (($emit | Where-Object { $_ -match '~' }).Count -eq 0) 'EmitBatEnv has no tilde paths'

Write-Host ""
Write-Host ("Result: {0} passed, {1} failed" -f $pass, $fail)
if ($fail -gt 0) { exit 1 } else { exit 0 }
