Set-Location 'D:\Smart\Claude-Code-Server'
Write-Output '=== sepidz@Admin ==='
Select-String -Path publish\*.ps1 -Pattern 'sepidz@Admin|hardcoded|Admin123|fallback.*sudo' | ForEach-Object { "$($_.Filename):$($_.LineNumber):$($_.Line.Trim().Substring(0,[Math]::Min(120,$_.Line.Trim().Length)))" }

Write-Output '=== || true in mac ==='
Select-String -Path scripts\client\mac\*.sh,scripts\client\git-mode.sh -Pattern '\|\| true' | ForEach-Object { "$($_.Filename):$($_.LineNumber):$($_.Line.Trim().Substring(0,[Math]::Min(100,$_.Line.Trim().Length)))" }

Write-Output '=== seq 1 4 ==='
Select-String -Path scripts\client\git-mode.sh,scripts\client\mac\connect.sh -Pattern 'seq 1 4' | ForEach-Object { "$($_.Filename):$($_.LineNumber):$($_.Line.Trim())" }

Write-Output '=== ReadAllBytes ==='
Select-String -Path scripts\client\*.ps1,scripts\client\windows\*.ps1 -Pattern 'ReadAllBytes' | ForEach-Object { "$($_.Filename):$($_.LineNumber)" }

Write-Output '=== ; true ==='
Select-String -Path scripts\client\mac\connect.sh,scripts\client\windows\connect.ps1,scripts\client\git-mode.ps1 -Pattern '; true' | ForEach-Object { "$($_.Filename):$($_.LineNumber):$($_.Line.Trim().Substring(0,[Math]::Min(120,$_.Line.Trim().Length)))" }

Write-Output '=== pipeline curly quote test ==='
Select-String -Path scripts\client\tests\test-connect-pipeline.ps1 -Pattern 'curly|smart.quote|0xE2|Unicode' -Context 0,3 | ForEach-Object { $_.Line }

Write-Output '=== FIX agents ==='
Get-ChildItem scripts\tmp\FIX-AGENT-*.md -EA SilentlyContinue | Select-Object Name
Write-Output '=== SoftFail DROP win ==='
Select-String -Path scripts\client\git-mode.ps1 -Pattern 'SoftFailCount|banner_miss|TUNNEL_DROP' | Select-Object -First 25 | ForEach-Object { "$($_.LineNumber):$($_.Line.Trim().Substring(0,[Math]::Min(110,$_.Line.Trim().Length)))" }
