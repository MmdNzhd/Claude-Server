$targets = @(
    @{ N='Smart'; S='smart@192.168.210.240'; Ip='192.168.210.240' },
    @{ N='Sepidz'; S='sepidz@192.168.250.70'; Ip='192.168.250.70' }
)
$fail = 0
foreach ($t in $targets) {
    Write-Host "$($t.N):" -ForegroundColor White
    try {
        $ver = (& ssh -o BatchMode=yes -o ConnectTimeout=12 $t.S "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt 2>/dev/null").Trim()
        $ip = (& ssh -o BatchMode=yes -o ConnectTimeout=12 $t.S "grep -o '192\.168\.[0-9.]*' /usr/local/share/claude-client/windows/connect.ps1 2>/dev/null | head -1").Trim()
        if (-not $ver) { Write-Host '  FAIL version missing' -ForegroundColor Red; $fail++; continue }
        if ($ip -ne $t.Ip) { Write-Host "  FAIL IP=$ip expected $($t.Ip)" -ForegroundColor Red; $fail++; continue }
        Write-Host "  OK v$ver IP=$ip" -ForegroundColor Green
    } catch {
        Write-Host "  FAIL $($_.Exception.Message)" -ForegroundColor Red
        $fail++
    }
}
exit $fail
