# test-connect-update-script-only-drift.ps1 - script-only deploy must not flag EXE content drift
# when local version matches remote and no local Claude-Connect.exe is present.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')

$fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== connect-update script-only drift gate ===' -ForegroundColor Cyan

$updPath = Get-ClientFile 'windows\connect-update.ps1'
$content = Get-Content -LiteralPath $updPath -Raw

$fnNames = @(
    'Get-SafeFileSha256',
    'Get-LocalConnectExePath',
    'Get-RemoteExeShaFromChecksums',
    'Test-LocalExeMatchesRemoteHash',
    'Test-LocalMatchesRemoteChecksums',
    'Test-RemoteVersionNewer',
    'Get-ConnectVersionParts',
    'Resolve-ConnectContentDrift'
)
foreach ($n in $fnNames) {
    $src = Get-FunctionSource -Content $content -Name $n
    if (-not $src) {
        Write-Host "  FAIL  could not extract $n from connect-update.ps1" -ForegroundColor Red
        exit 1
    }
    . ([scriptblock]::Create($src))
}

$script:UpdateLog = New-Object System.Collections.Generic.List[string]
function Write-UpdateFileLog {
    param([string]$Message, [string]$Level = 'INFO')
    [void]$script:UpdateLog.Add($Message)
}

$RemoteBundle = '/usr/local/share/claude-client'
$fakeExeHash = ('a' * 64)
$mockChecksums = "$fakeExeHash *Claude-Connect.exe"
$sshCatCalls = New-Object System.Collections.Generic.List[string]
function Invoke-SshCat {
    param([string]$Target, [string]$RemotePath)
    [void]$sshCatCalls.Add($RemotePath)
    if ($RemotePath -like '*/checksums.txt') { return $script:MockChecksumsText }
    return $null
}

$ver = '20260726.05'
$tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ("cc-script-only-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
$script:ScriptDir = $tmpRoot
$origUserProfile = $env:USERPROFILE
$fakeHome = Join-Path $tmpRoot 'home'
New-Item -ItemType Directory -Force -Path $fakeHome | Out-Null
$env:USERPROFILE = $fakeHome

try {
    New-Item -ItemType Directory -Force -Path $script:ScriptDir | Out-Null
    Set-Content -LiteralPath (Join-Path $script:ScriptDir 'connect-version.txt') -Value $ver -NoNewline -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $script:ScriptDir 'connect.ps1') -Value '$ServerIP = "192.168.210.240"' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $script:ScriptDir 'connect-update.ps1') -Value '# fixture' -Encoding UTF8

    Assert (-not (Get-LocalConnectExePath)) 'fixture has no local Claude-Connect.exe'

    $script:UpdateLog.Clear()
    $sshCatCalls.Clear()
    $script:MockChecksumsText = $mockChecksums

    $result = Resolve-ConnectContentDrift -RemoteVer $ver -LocalVer $ver -Target 'smart@192.168.210.240'

    $log = ($script:UpdateLog -join "`n")
    Assert (-not $result.VersionNewer) 'equal versions are not newer'
    Assert (-not $result.ContentDrift) 'script-only + version match must not set contentDrift'
    Assert ($log -match 'drift_gate=script_only_ok') 'script-only deploy must skip EXE drift'
    Assert ($log -notmatch 'drift_gate=exe_mismatch') 'must not treat missing EXE as mismatch when versions equal'
    Assert ($log -notmatch 'local_exe_missing drift=1') 'must not log local_exe_missing drift when script-only'
    Assert ($sshCatCalls.Count -eq 0) 'must not SSH-fetch checksums.txt when no local EXE and versions match'
} finally {
    $env:USERPROFILE = $origUserProfile
    Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1

