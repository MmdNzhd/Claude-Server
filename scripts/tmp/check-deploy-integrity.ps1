$p='D:\Smart\Claude-Code-Server\publish\deploy-client-bundles.ps1'
$c=Get-Content $p -Raw
Write-Host ("Build-AutoUpdate count=" + ([regex]::Matches($c,'function Build-AutoUpdateBundleStage')).Count)
Write-Host ("Test-RemoteVersionMatches count=" + ([regex]::Matches($c,'function Test-RemoteVersionMatches')).Count)
Write-Host ("ExpectedVersion param=" + ($c -match 'ExpectedVersion'))
Write-Host ("version mismatch throw=" + ($c -match 'Remote version mismatch'))
$errs=$null
$null=[System.Management.Automation.Language.Parser]::ParseFile($p,[ref]$null,[ref]$errs)
Write-Host ("parse_errors=" + $(if($errs){$errs.Count}else{0}))
# repo version
Write-Host ("repo_ver=" + (Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-version.txt' -Raw).Trim())
Write-Host ("has_tunnel_fix=" + [bool](Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1' -Pattern 'Test-TunnelBannerIsWindows -Banner \$banner' -Quiet))
Write-Host ("has_auth_fix=" + [bool](Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\cursor-auth-laptop.ps1' -Pattern 'Get-CursorAuthTempRoot' -Quiet))
