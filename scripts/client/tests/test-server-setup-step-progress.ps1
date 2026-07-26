# test-server-setup-step-progress.ps1 - Server setup mid-step UI progress (A)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== Server setup step progress (A) ===' -ForegroundColor Cyan

$c = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
Assert ($c -match 'function\s+Update-StepProgress\b') 'Update-StepProgress defined'
Assert ($c -match '\$script:StepProgressActive') 'StepProgressActive script flag present'

$init = Get-FunctionSource -Content $c -Name 'Initialize-ServerSession'
Assert ($init.Length -gt 200) 'extracted Initialize-ServerSession'
Assert (($init -split 'Update-StepProgress').Count -ge 4) 'Initialize-ServerSession calls Update-StepProgress at least 3 times'
Assert ($init -match "Update-StepProgress\s+'key'") 'progress: key'
Assert ($init -match "Update-StepProgress\s+'port'") 'progress: port'
Assert ($init -match "Update-StepProgress\s+'conf'") 'progress: conf'

$stepOk = Get-FunctionSource -Content $c -Name 'StepOk'
Assert ($stepOk -match 'StepProgressActive') 'StepOk rewrites line when progress was shown'
Assert ($stepOk -match 'Write-Host " \$d"') 'StepOk keeps classic append path when no progress'

Write-Host ''
if ($fail -eq 0) { Write-Host 'All tests passed.' -ForegroundColor Green; exit 0 }
Write-Host "$fail test(s) failed." -ForegroundColor Red; exit 1
