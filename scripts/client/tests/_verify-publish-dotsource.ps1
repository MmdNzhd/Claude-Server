# _verify-publish-dotsource.ps1 - ensure published windows bundle dot-sources on PS 5.1
$ErrorActionPreference = 'Stop'
$pub = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260705\windows'
if (-not (Test-Path $pub)) {
    Write-Host "FAIL  publish folder missing: $pub" -ForegroundColor Red
    exit 1
}
$files = @('editor-launch.ps1', 'git-mode.ps1', 'connect-ui.ps1', 'cursor-auth-laptop.ps1')
foreach ($name in $files) {
    $path = Join-Path $pub $name
    $errs = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errs)
    if ($errs -and $errs.Count -gt 0) {
        Write-Host "FAIL  $name parse: $($errs[0].Message)" -ForegroundColor Red
        exit 1
    }
    Write-Host "PASS  $name parses" -ForegroundColor Green
}
. (Join-Path $pub 'editor-launch.ps1')
. (Join-Path $pub 'git-mode.ps1')
. (Join-Path $pub 'connect-ui.ps1')
. (Join-Path $pub 'cursor-auth-laptop.ps1')
$need = @(
    'Sanitize-SshAliasConfig', 'Acquire-TunnelPort', 'Ensure-SessionTunnel',
    'Push-ServerConnectConf', 'Get-GitMode', 'Launch-RemoteEditor',
    'Write-ConnectHeader', 'Sync-CursorGoldenAuth'
)
foreach ($fn in $need) {
    if (-not (Get-Command $fn -ErrorAction SilentlyContinue)) {
        Write-Host "FAIL  missing function $fn after dot-source" -ForegroundColor Red
        exit 1
    }
    Write-Host "PASS  $fn loaded" -ForegroundColor Green
}
foreach ($rp in @('D:\Smart\test', 'D:/Smart/test')) {
    try {
        $null = Test-LaptopRpathCompatible -Rpath $rp -Os 'windows'
    } catch {
        Write-Host "FAIL  Test-LaptopRpathCompatible throws on $rp : $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
    Write-Host "PASS  Test-LaptopRpathCompatible $rp" -ForegroundColor Green
}
$gmSrc = Get-Content (Join-Path $pub 'git-mode.ps1') -Raw
if ($gmSrc -match "-replace '\\',") {
    Write-Host 'FAIL  git-mode.ps1 uses invalid -replace backslash regex' -ForegroundColor Red
    exit 1
}
Write-Host 'PASS  git-mode.ps1 uses literal path slash normalize' -ForegroundColor Green
$bat = Get-Content (Join-Path $pub 'connect.bat') -Raw
if ($bat -notmatch 'Acquire-TunnelPort') {
    Write-Host 'FAIL  connect.bat missing Acquire-TunnelPort guard' -ForegroundColor Red
    exit 1
}
Write-Host 'PASS  connect.bat guards Acquire-TunnelPort' -ForegroundColor Green
Write-Host 'All publish dot-source checks passed.' -ForegroundColor Green
