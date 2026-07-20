$ErrorActionPreference='Stop'
$gm='D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1'
# exact lines 182-220
$lines=Get-Content $gm
182..220 | ForEach-Object { "{0,4}|{1}" -f $_, $lines[$_-1] }
Write-Output '---'
# also check if Desktop pack has same bug
$desk=Join-Path $env:USERPROFILE 'Desktop\claude-publish'
Get-ChildItem $desk -Directory -Filter 'claude-code-*' -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending | Select-Object -First 4 |
  ForEach-Object {
    $p=Join-Path $_.FullName 'windows\git-mode.ps1'
    if (-not (Test-Path $p)) { $p=Join-Path $_.FullName 'claude-code\windows\git-mode.ps1' }
    if (Test-Path $p) {
      $m=Select-String -Path $p -Pattern 'function Test-TunnelBannerIsThisLaptop' -Context 0,5
      Write-Output "PACK $($_.Name):"
      $m | ForEach-Object { $_.Context.PostContext; $_.Line }
    }
  }
Write-Output '=== deploy InstallBundle function signature area ==='
$d='D:\Smart\Claude-Code-Server\publish\deploy-client-bundles.ps1'
Select-String -Path $d -Pattern 'function Install-|ExpectedVersion|ClientRoot|connect-version' |
  ForEach-Object { "$($_.LineNumber):$($_.Line.Trim())" }
# find function that contains remoteVer check
Select-String -Path $d -Pattern 'function ' | ForEach-Object { "$($_.LineNumber):$($_.Line.Trim())" }
