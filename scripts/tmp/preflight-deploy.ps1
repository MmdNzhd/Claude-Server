#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $ProjectRoot 'publish\Get-DeployCredentials.ps1')

Write-Host '=== Sepidz sudo preflight ==='
$t = Get-SepidzServerTarget
$pw = Get-SepidzSudoPassword
Write-Host ("target={0} pw_len={1}" -f $t, $pw.Length)
$tmpIn = Join-Path $env:TEMP ("sepidz-sudo-in-{0}.txt" -f [guid]::NewGuid().ToString('N'))
$tmpOut = Join-Path $env:TEMP ("sepidz-sudo-out-{0}.txt" -f [guid]::NewGuid().ToString('N'))
$tmpErr = Join-Path $env:TEMP ("sepidz-sudo-err-{0}.txt" -f [guid]::NewGuid().ToString('N'))
[IO.File]::WriteAllText($tmpIn, $pw + "`n")
$p = Start-Process -FilePath ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=15','-o','IdentitiesOnly=yes','-o','IdentityAgent=none',$t,'sudo -S -v && echo SEPIDZ_SUDO_OK') -RedirectStandardInput $tmpIn -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr -NoNewWindow -PassThru
if (-not $p.WaitForExit(25000)) { try { $p.Kill() } catch {}; Write-Host 'sepidz_sudo=TIMEOUT'; exit 2 }
Write-Host ("sepidz_sudo_exit={0}" -f $p.ExitCode)
$o = Get-Content $tmpOut -Raw -ErrorAction SilentlyContinue
$e = Get-Content $tmpErr -Raw -ErrorAction SilentlyContinue
Write-Host ("out={0}" -f (($o -replace '\s+',' ').Trim()))
# do not print password; only show if stderr mentions incorrect/password
if ($e -match 'incorrect|Sorry|auth') { Write-Host 'err=AUTH_FAIL_HINT' } else { Write-Host ("err_len={0}" -f ($(if($e){$e.Length}else{0}))) }
Remove-Item $tmpIn,$tmpOut,$tmpErr -Force -ErrorAction SilentlyContinue
if ($p.ExitCode -ne 0) { exit 1 }
Write-Host 'SEPIDZ_PREFLIGHT_OK'
