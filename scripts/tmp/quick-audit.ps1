function Query($label, $target, $expectIp) {
    $outFile = Join-Path $env:TEMP "audit-$label.out"
    Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=5',$target,"test -f /usr/local/share/claude-client/connect.ps1 && tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt && grep -o '192.168.[0-9.]*' /usr/local/share/claude-client/connect.ps1 | head -1 && bash -n /usr/local/share/claude-client/mac/claude-mount.sh && echo mount=OK || echo MISSING") -NoNewWindow -Wait -PassThru -RedirectStandardOutput $outFile | Out-Null
    $lines = @(Get-Content $outFile -ErrorAction SilentlyContinue)
    Write-Host "$label : $($lines -join ' | ') (expect $expectIp)"
}
Query 'Smart' 'smart@192.168.210.240' '192.168.210.240'
Query 'Sepidz' 'sepidz@192.168.250.70' '192.168.250.70'
