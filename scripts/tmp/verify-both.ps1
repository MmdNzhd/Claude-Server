function Q($label, $target, $expect) {
    $f = Join-Path $env:TEMP "v-$label.txt"
    Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=8',$target,'test -f /usr/local/share/claude-client/connect.ps1 && cat /usr/local/share/claude-client/connect-version.txt && grep -o "192.168.[0-9.]*" /usr/local/share/claude-client/connect.ps1 | head -1 && bash -n /usr/local/share/claude-client/mac/claude-mount.sh && echo OK || echo MISSING') -NoNewWindow -Wait -PassThru -RedirectStandardOutput $f | Out-Null
    $lines = @(Get-Content $f -ErrorAction SilentlyContinue)
    Write-Host "$label : $($lines -join ' | ') (expect $expect)"
}
Q Smart smart@192.168.210.240 192.168.210.240
Q Sepidz sepidz@192.168.250.70 192.168.250.70
