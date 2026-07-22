
$ErrorActionPreference = 'Continue'
$runner = Join-Path $env:TEMP 'claude-connect-wmcp\ensure-bg.ps1'
$mod = (Resolve-Path 'scripts/client/windows/windows-mcp-laptop.ps1').Path
Write-Output "MOD=$mod"
Write-Output "RUNNER_BYTES=$((Get-Item $runner).Length)"
Write-Output '---RUNNER HEAD---'
Get-Content -LiteralPath $runner -TotalCount 40
Write-Output '---RUN SYNC CHILD---'
$outLog = Join-Path $env:TEMP 'claude-connect-wmcp\ensure-bg-out.txt'
$errLog = Join-Path $env:TEMP 'claude-connect-wmcp\ensure-bg-err.txt'
# Reproduce Start-Process ArgumentList array style (current code)
$argList = @(
  '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden',
  '-File', $runner, '-ModulePath', $mod, '-SshAlias', 'claude-server'
)
Write-Output ("ARGLIST_JOIN=" + ($argList -join ' | '))
$p = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $outLog -RedirectStandardError $errLog
Write-Output "EXIT_ARRAY_STYLE=$($p.ExitCode)"
Write-Output 'OUT_ARRAY:'
Get-Content $outLog -EA SilentlyContinue
Write-Output 'ERR_ARRAY:'
Get-Content $errLog -EA SilentlyContinue

# Fixed quoting style
$argStr = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -ModulePath "{1}" -SshAlias "{2}"' -f $runner, $mod, 'claude-server'
$out2 = Join-Path $env:TEMP 'claude-connect-wmcp\ensure-bg-out2.txt'
$err2 = Join-Path $env:TEMP 'claude-connect-wmcp\ensure-bg-err2.txt'
$p2 = Start-Process -FilePath 'powershell.exe' -ArgumentList $argStr -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $out2 -RedirectStandardError $err2
Write-Output "EXIT_QUOTED_STYLE=$($p2.ExitCode)"
Write-Output 'OUT_QUOTED:'
Get-Content $out2 -EA SilentlyContinue
Write-Output 'ERR_QUOTED:'
Get-Content $err2 -EA SilentlyContinue
Write-Output '---LOG TAIL---'
Get-Content (Join-Path $env:USERPROFILE '.config\claude-connect\logs\windows-mcp-ensure.log') -Tail 15
