# test-connect-ui.ps1 — layout helper tests
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
. (Join-Path $ClientRoot 'connect-ui.ps1')

function Assert($cond, $msg) {
    if (-not $cond) { throw "FAIL: $msg" }
}

Assert ((Get-TerminalWidth) -ge 40) 'width floor 40'
Assert ((Get-LayoutTier 65) -eq 'narrow') 'tier narrow at 65'
Assert ((Get-LayoutTier 80) -eq 'normal') 'tier normal at 80'
Assert ((Get-LayoutTier 120) -eq 'wide') 'tier wide at 120'
Assert ((Format-TruncPath 'D:\Smart\Very\Long\Path\ai' 20).Length -le 20) 'trunc path length'

$src = Get-Content (Join-Path $ClientRoot 'connect-ui.ps1') -Raw
Assert ($src -notmatch 'SetWindowSize|Set_BufferSize') 'no console resize'

Write-Host 'OK test-connect-ui.ps1' -ForegroundColor Green
