$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'

# Sepidz
$outS=Join-Path $env:TEMP 'ver-sepidz.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=10','sepidz@192.168.250.70','cat /usr/local/share/claude-client/connect-version.txt') -NoNewWindow -PassThru -RedirectStandardOutput $outS -RedirectStandardError ($outS+'.err')
[void]$p.WaitForExit(20000)
$sepidz=((Get-Content $outS -Raw)+'').Trim()

# Smart - need smart credentials / smart@IP
$smartTarget='smart@192.168.210.240'
$outM=Join-Path $env:TEMP 'ver-smart.out'
$p2=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=10',$smartTarget,'cat /usr/local/share/claude-client/connect-version.txt') -NoNewWindow -PassThru -RedirectStandardOutput $outM -RedirectStandardError ($outM+'.err')
[void]$p2.WaitForExit(20000)
$smart=((Get-Content $outM -Raw -ErrorAction SilentlyContinue)+'').Trim()
$err=((Get-Content ($outM+'.err') -Raw -ErrorAction SilentlyContinue)+'').Trim()

Write-Host "SEPIDZ_BUNDLE=$sepidz"
Write-Host "SMART_BUNDLE=$smart"
if($err){ Write-Host "SMART_ERR=$err" }

# Confirm recent publish was SepidzOnly - check version files in repo
$ver=[IO.File]::ReadAllText('D:\Smart\Claude-Code-Server\scripts\client\windows\connect-version.txt').Trim()
Write-Host "REPO_CLIENT_VER=$ver"
Write-Host "POLICY=SepidzOnly Smart must stay 20260717.22"
if($smart -and $smart -ne '20260717.22'){
  Write-Host 'WARNING_SMART_CHANGED'
  exit 2
}
if($smart -eq '20260717.22'){ Write-Host 'SMART_FROZEN_OK' }
