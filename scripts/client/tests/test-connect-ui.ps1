# test-connect-ui.ps1 - layout helper tests
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
. (Join-Path $ClientRoot 'git-mode.ps1')
. (Join-Path $ClientRoot 'connect-ui.ps1')

function Assert($cond, $msg) {
    if (-not $cond) { throw "FAIL: $msg" }
}

Assert ((Get-TerminalWidth) -ge 40) 'width floor 40'
Assert ((Get-LayoutTier 65) -eq 'narrow') 'tier narrow at 65'
Assert ((Get-LayoutTier 80) -eq 'normal') 'tier normal at 80'
Assert ((Get-LayoutTier 120) -eq 'wide') 'tier wide at 120'
Assert ((Format-TruncPath 'D:\Smart\Very\Long\Path\ai' 20).Length -le 20) 'trunc path length'
Assert ((Format-TruncLabel 'Automation Preivew' 14) -eq 'Automation ...') 'trunc long label'

$mounts = @(
    [PSCustomObject]@{ Id = 'ai'; Label = 'Ai'; Rpath = 'D:/Personnal/ai'; Active = $false }
    [PSCustomObject]@{ Id = 'ccs'; Label = 'Claude Code Server'; Rpath = 'D:/Smart/Claude-Code-Server'; Active = $false }
    [PSCustomObject]@{ Id = 'auto'; Label = 'Automation Preivew'; Rpath = 'D:/Smart/Automation-Preivew'; Active = $true }
)
Assert ((Get-ProjectNameColWidth -Mounts $mounts -TerminalWidth 80 -PathMax 36) -ge 27) 'name col fits longest label plus active tag'
$line = ("    {0,2}  {1,-27}  {2}" -f 4, 'Automation Preivew (active)', 'D:/Smart/Automation-Preivew')
Assert ($line -match 'Automation Preivew \(active\)\s+D:') 'format keeps name and path columns apart'

$src = Get-Content (Join-Path $ClientRoot 'connect-ui.ps1') -Raw
$connectUiSh = Get-Content (Join-Path $ClientRoot 'connect-ui.sh') -Raw
Assert ($src -notmatch 'SetWindowSize|Set_BufferSize') 'no console resize'
Assert ($connectUiSh -match 'ui_session_status_line') 'connect-ui.sh has session status line'


Assert ((Get-LaptopRpathOsHint -Rpath 'D:/temp' -Os 'mac') -eq 'Windows only') 'Mac client marks Windows paths'
Assert (-not (Test-LaptopRpathCompatible -Rpath 'D:/temp' -Os 'mac')) 'D drive blocked on Mac'
$uiSh = Get-Content (Join-Path $ClientRoot 'connect-ui.sh') -Raw
Assert ($uiSh -notmatch 'Enter = .*project') 'no Enter=last project hint in connect-ui.sh'

Write-Host 'OK test-connect-ui.ps1' -ForegroundColor Green
