$ErrorActionPreference='Continue'
function SshOut($target,$cmd){
  $o="$env:TEMP\fc-$([guid]::NewGuid().ToString('N').Substring(0,6)).out"
  $e="$o.err"
  $p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=8',$target,$cmd) -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
  [void]$p.WaitForExit(15000)
  return ((Get-Content $o -Raw -EA SilentlyContinue)+'').Trim()
}
Write-Host ("SEPIDZ_LIVE=" + (SshOut 'sepidz@192.168.250.70' 'cat /usr/local/share/claude-client/connect-version.txt'))
Write-Host ("SMART_LIVE=" + (SshOut 'smart@192.168.210.240' 'cat /usr/local/share/claude-client/connect-version.txt'))
$bad='C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260717\claude-code\windows'
$good='C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260718\claude-code\windows'
foreach($d in @($bad,$good)){
  $v=(Get-Content (Join-Path $d 'connect-version.txt') -Raw).Trim()
  $ip=[regex]::Match((Get-Content (Join-Path $d 'connect.ps1') -Raw),'192\.168\.\d+\.\d+').Value
  Write-Host "$d => ver=$v ip=$ip"
}
Write-Host 'DONE'
