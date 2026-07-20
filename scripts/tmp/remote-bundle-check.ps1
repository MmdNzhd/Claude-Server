$checks = @(
    @{ Name='Smart'; Server='smart@192.168.210.240'; ExpectedIp='192.168.210.240' },
    @{ Name='Sepidz'; Server='sepidz@192.168.250.70'; ExpectedIp='192.168.250.70' }
)
$fail = 0
foreach ($c in $checks) {
    Write-Host "$($c.Name) server:" -ForegroundColor White
    $ver = (ssh -o BatchMode=yes -o ConnectTimeout=12 $c.Server "cat /usr/local/share/claude-client/connect-version.txt 2>/dev/null").Trim()
    $ip = (ssh -o BatchMode=yes -o ConnectTimeout=12 $c.Server "grep -o $($c.ExpectedIp) /usr/local/share/claude-client/windows/connect.ps1 2>/dev/null | Select-Object -First 1").Trim()
    $install = (ssh -o BatchMode=yes -o ConnectTimeout=12 $c.Server "if (Test-Path /usr/local/lib/claude-server/commands/install-client-bundle.sh) { 'ok' } else { 'missing' }" 2>$null)
    if (-not $install) {
        $install = (ssh -o BatchMode=yes -o ConnectTimeout=12 $c.Server "test -f /usr/local/lib/claude-server/commands/install-client-bundle.sh && echo ok || echo missing").Trim()
    }
    if ($ver) { Write-Host "  version v$ver" -ForegroundColor Green } else { Write-Host '  version MISSING' -ForegroundColor Red; $fail++ }
    if ($ip -eq $c.ExpectedIp) { Write-Host "  IP $ip" -ForegroundColor Green } else { Write-Host "  IP wrong: '$ip'" -ForegroundColor Red; $fail++ }
    if ($install -eq 'ok') { Write-Host '  install-client-bundle.sh ok' -ForegroundColor Green } else { Write-Host "  install script: $install" -ForegroundColor Red; $fail++ }
}
if ($fail -eq 0) { Write-Host 'Remote OK' -ForegroundColor Green; exit 0 }
Write-Host "Remote FAIL ($fail)" -ForegroundColor Red; exit 1
