function SshOut($t,$c){
  $o=Join-Path $env:TEMP ('c'+[guid]::NewGuid().ToString('N').Substring(0,6)+'.out')
  $p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=8',$t,$c) -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError ($o+'.err')
  [void]$p.WaitForExit(15000)
  return ((Get-Content $o -Raw -ErrorAction SilentlyContinue)+'').Trim()
}
Write-Host ('SMART_LIVE='+(SshOut 'smart@192.168.210.240' 'cat /usr/local/share/claude-client/connect-version.txt'))
Write-Host ('SEPIDZ_LIVE='+(SshOut 'sepidz@192.168.250.70' 'cat /usr/local/share/claude-client/connect-version.txt'))
Write-Host ('REPO='+((Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-version.txt' -Raw).Trim()))
