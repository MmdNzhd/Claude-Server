$ErrorActionPreference='Continue'
Set-Location 'D:\Smart\Claude-Code-Server'
$fail=@()

function Hit($name,$ok,$detail){
  if($ok){ "PASS $name" } else { "FAIL $name :: $detail"; $script:fail += $name }
}

# Reports
Write-Output '=== FIX/VERIFY REPORTS ==='
Get-ChildItem scripts\tmp\FIX-W*.md,scripts\tmp\VERIFY-ALL-FIXED.md,scripts\tmp\FIX-AGENT-*.md -EA SilentlyContinue |
  ForEach-Object { $_.Name + ' ' + $_.Length }

# 1 curly
$t=[IO.File]::ReadAllText('scripts\client\windows\connect.ps1')
Hit 'curly-quotes' ($t -notmatch '[\u201C\u201D\u2018\u2019]') 'still has curly'

# 2 seq 1 12 not 4
$gm=[IO.File]::ReadAllText('scripts\client\git-mode.sh')
Hit 'mac-wait-12' ($gm -match 'seq 1 12' -and $gm -notmatch 'seq 1 4') "seq4=$($gm -match 'seq 1 4') seq12=$($gm -match 'seq 1 12')"

# 3 recover mangle
$rec = Select-String -Path scripts\client\git-mode.sh -Pattern 'recover_mounts_if_needed|recover-one' -Context 0,15 |
  Out-String
$mangle = $gm -match 'timeout 30 sshx "\$CM recover-one.*sshx "\$CM'
Hit 'mac-recover-no-nested-sshx' (-not $mangle) 'nested sshx still present'

# 4 banner_miss reset SoftFailCount=0 near banner_miss
$gmp=Get-Content scripts\client\git-mode.ps1 -Raw
# crude: after banner_miss_tcp_open within 15 lines SoftFailCount = 0 without ++
$lines=Get-Content scripts\client\git-mode.ps1
$badBanner=$false
for($i=0;$i -lt $lines.Count;$i++){
  if($lines[$i] -match 'banner_miss_tcp_open'){
    $window=($lines[$i..([Math]::Min($i+12,$lines.Count-1))] -join "`n")
    if($window -match 'SoftFailCount\s*=\s*0' -and $window -notmatch 'SoftFailCount\+\+'){ $badBanner=$true; "banner_miss context L$($i+1)" }
  }
}
Hit 'win-banner-miss-budget' (-not $badBanner) 'resets SoftFailCount=0'

# 5 SoftFail >=6 hard return
Hit 'win-softfail-hard' ($gmp -match 'TunnelSoftFailCount\s*-ge\s*6' -or $gmp -match 'SoftFailCount\s*-ge\s*6') 'no -ge 6 hard path'

# 6 auth temp
$auth=Get-Content scripts\client\cursor-auth-laptop.ps1 -Raw
Hit 'auth-temp-helpers' ($auth -match 'Get-CursorAuthTempRoot' -and $auth -match 'Remove-CursorAuthTempDir') 'missing helpers'
$bare=Select-String -Path scripts\client\cursor-auth-laptop.ps1 -Pattern 'Remove-Item \$tmp -Recurse'
Hit 'auth-no-bare-recurse-tmp' (-not $bare) "$bare"

# 7 sepidz fallback in publish scripts (not local.ps1)
$fb=Select-String -Path publish\Get-DeployCredentials.ps1,publish\deploy-client-bundles.ps1 -Pattern "SepidzSudoPassword\s*=\s*'[^']+'" -EA SilentlyContinue
Hit 'no-hardcoded-sudo-in-publish' (-not $fb) "$fb"

Write-Output "=== SUMMARY fail_count=$($fail.Count) fails=$($fail -join ',') ==="

# quick pipeline curly-only + full if fast
Write-Output '=== RUN pipeline ==='
$p=Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','D:\Smart\Claude-Code-Server\scripts\client\tests\test-connect-pipeline.ps1') -WorkingDirectory 'D:\Smart\Claude-Code-Server\scripts\client\tests' -NoNewWindow -PassThru -RedirectStandardOutput 'D:\Smart\Claude-Code-Server\scripts\tmp\pipe2.txt' -RedirectStandardError 'D:\Smart\Claude-Code-Server\scripts\tmp\pipe2.err'
[void]$p.WaitForExit(180000)
"pipeline_exit=$($p.ExitCode)"
Select-String -Path scripts\tmp\pipe2.txt -Pattern 'FAIL |failed\.|All .*passed' | ForEach-Object { $_.Line }
