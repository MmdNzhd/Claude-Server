function SshOut($t,$c){ $o=Join-Path $env:TEMP ('x'+[guid]::NewGuid().ToString('N').Substring(0,6)+'.out'); $p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=8',$t,$c) -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError ($o+'.err'); [void]$p.WaitForExit(15000); return ((Get-Content $o -Raw -EA SilentlyContinue)+'').Trim() }
Write-Host ('SEPIDZ_LIVE='+(SshOut 'sepidz@192.168.250.70' 'cat /usr/local/share/claude-client/connect-version.txt'))
Write-Host ('SMART_LIVE='+(SshOut 'smart@192.168.210.240' 'cat /usr/local/share/claude-client/connect-version.txt'))
Write-Host 'DEEP_FIX_OK'
