#Requires -Version 5.1
$ErrorActionPreference = 'Continue'
$key = Join-Path $env:USERPROFILE '.ssh\claude_laptop'
$target = 'smart@192.168.210.240'

# Prefer stored Smart sudo password if present (optional local file)
$smartLocal = 'D:\Smart\Claude-Code-Server\publish\smart-deploy.local.ps1'
$sudoPw = $env:SMART_SUDO_PASSWORD
if (-not $sudoPw -and (Test-Path $smartLocal)) {
  $c = Get-Content $smartLocal -Raw
  if ($c -match "SmartSudoPassword\s*=\s*'([^']*)'") { $sudoPw = $Matches[1] }
  if ($c -match 'SmartSudoPassword\s*=\s*"([^"]*)"') { $sudoPw = $Matches[1] }
}

$install = "chmod +x ~/claude-client-bundle-deploy/install-client-bundle.sh && sudo -n bash ~/claude-client-bundle-deploy/install-client-bundle.sh ~/claude-client-bundle-deploy/bundle.zip"

Write-Host 'Smart: trying passwordless sudo...' -ForegroundColor Cyan
$a = @('-o','ControlMaster=no','-i',$key,'-o','BatchMode=yes','-o','ConnectTimeout=15',$target,$install)
$p = Start-Process -FilePath ssh -ArgumentList $a -NoNewWindow -PassThru -Wait -RedirectStandardOutput "$env:TEMP\smart-inst.out" -RedirectStandardError "$env:TEMP\smart-inst.err"
Write-Host ("nopass exit=" + $p.ExitCode)

if ($p.ExitCode -ne 0 -and $sudoPw) {
  Write-Host 'Smart: installing with stored sudo password...' -ForegroundColor Cyan
  $escaped = $sudoPw.Replace("'", "'\''")
  $pwCmd = "bash -lc `"echo '$escaped' | sudo -S bash ~/claude-client-bundle-deploy/install-client-bundle.sh ~/claude-client-bundle-deploy/bundle.zip`""
  $a2 = @('-o','ControlMaster=no','-i',$key,'-o','BatchMode=yes','-o','ConnectTimeout=120',$target,$pwCmd)
  $p2 = Start-Process -FilePath ssh -ArgumentList $a2 -NoNewWindow -PassThru -Wait -RedirectStandardOutput "$env:TEMP\smart-inst2.out" -RedirectStandardError "$env:TEMP\smart-inst2.err"
  Write-Host ("pass exit=" + $p2.ExitCode)
  if (Test-Path "$env:TEMP\smart-inst2.out") { Get-Content "$env:TEMP\smart-inst2.out" }
  if (Test-Path "$env:TEMP\smart-inst2.err") { Get-Content "$env:TEMP\smart-inst2.err" | Select-Object -First 20 }
}

# Verify
$verCmd = 'echo version=$(tr -d "\r\n" < /usr/local/share/claude-client/connect-version.txt); EL=/usr/local/share/claude-client/editor-launch.ps1; echo preserve=$(grep -c preserve_open_windows "$EL"); echo force=$(grep -c pre_launch_agent_or_new_window "$EL"); echo retry=$(grep -c LAUNCH_RETRY_NO_KILL "$EL")'
$av = @('-o','ControlMaster=no','-i',$key,'-o','BatchMode=yes','-o','ConnectTimeout=10',$target,$verCmd)
$pv = Start-Process -FilePath ssh -ArgumentList $av -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\smart-ver.out" -RedirectStandardError "$env:TEMP\smart-ver.err"
[void]$pv.WaitForExit(15000)
Write-Host '=== SMART VERIFY ===' -ForegroundColor White
Get-Content "$env:TEMP\smart-ver.out" -ErrorAction SilentlyContinue

$ver = ''
if (Test-Path "$env:TEMP\smart-ver.out") {
  $m = Select-String -Path "$env:TEMP\smart-ver.out" -Pattern 'version=(\S+)' | Select-Object -First 1
  if ($m) { $ver = $m.Matches[0].Groups[1].Value }
}
if ($ver -ne '20260715.18') {
  Write-Host ''
  Write-Host 'Opening interactive sudo window for Smart install. Enter password there.' -ForegroundColor Yellow
  $title = 'Claude bundle install - Smart - ENTER SUDO PASSWORD'
  $sshCmd = "ssh -t -o ControlMaster=no -i `"$key`" -o ConnectTimeout=15 $target `"chmod +x ~/claude-client-bundle-deploy/install-client-bundle.sh && sudo bash ~/claude-client-bundle-deploy/install-client-bundle.sh ~/claude-client-bundle-deploy/bundle.zip; echo; echo DONE_EXIT=`$?; exec bash`""
  Start-Process cmd.exe -ArgumentList @('/k', "title $title && $sshCmd")
  $deadline = (Get-Date).AddSeconds(180)
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    $pv2 = Start-Process -FilePath ssh -ArgumentList $av -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\smart-ver2.out" -RedirectStandardError "$env:TEMP\smart-ver2.err"
    [void]$pv2.WaitForExit(12000)
    $line = Get-Content "$env:TEMP\smart-ver2.out" -ErrorAction SilentlyContinue | Select-Object -First 1
    Write-Host ("poll: " + $line)
    if ($line -match 'version=20260715\.18') {
      Write-Host 'Smart deploy SUCCESS' -ForegroundColor Green
      Get-Content "$env:TEMP\smart-ver2.out"
      exit 0
    }
  }
  Write-Host 'Timed out waiting for Smart sudo. Complete the opened window, then re-check.' -ForegroundColor Red
  exit 1
} else {
  Write-Host 'Smart already at 20260715.18' -ForegroundColor Green
  exit 0
}
