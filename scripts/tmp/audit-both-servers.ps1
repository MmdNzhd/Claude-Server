foreach ($t in @(
    @{L='Smart';S='smart@192.168.210.240';IP='192.168.210.240'},
    @{L='Sepidz';S='smart@192.168.250.70';IP='192.168.250.70'}
)) {
    Write-Host "`n$($t.L) ($($t.S))" -ForegroundColor Cyan
    $out = & ssh -o BatchMode=yes -o ConnectTimeout=10 $t.S @"
if [ ! -d /usr/local/share/claude-client ]; then echo STATUS=MISSING; exit 0; fi
ver=`$(tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt 2>/dev/null)
ip=`$(grep -o '192.168.[0-9.]*' /usr/local/share/claude-client/connect.ps1 2>/dev/null | head -1)
bash -n /usr/local/share/claude-client/mac/claude-mount.sh >/dev/null 2>&1 && m=OK || m=FAIL
echo STATUS=OK
echo version=`$ver
echo ip=`$ip
echo mount=`$m
test \"`$ip\" = \"$($t.IP)\" && echo ip_ok=yes || echo ip_ok=no
"@
    $out | ForEach-Object { Write-Host "  $_" }
}
