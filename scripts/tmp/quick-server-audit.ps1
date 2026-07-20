$out = Join-Path $PSScriptRoot 'audit-result.txt'
$lines = New-Object System.Collections.Generic.List[string]
foreach ($t in @(
    @{L='Smart';S='smart@192.168.210.240';IP='192.168.210.240'},
    @{L='Sepidz';S='smart@192.168.250.70';IP='192.168.250.70'}
)) {
    $lines.Add("=== $($t.L) ===")
    & ssh -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1 $t.S "echo ok" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { $lines.Add("SSH: FAIL ($LASTEXITCODE)"); continue }
    $lines.Add("SSH: OK")
    $ver = (& ssh -o BatchMode=yes -o ConnectTimeout=5 $t.S "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt 2>/dev/null").Trim()
    $ip = (& ssh -o BatchMode=yes -o ConnectTimeout=5 $t.S "grep -o '192.168.[0-9.]*' /usr/local/share/claude-client/connect.ps1 2>/dev/null | head -1").Trim()
    $mount = (& ssh -o BatchMode=yes -o ConnectTimeout=5 $t.S "bash -n /usr/local/share/claude-client/mac/claude-mount.sh 2>&1; echo exit=$?").Trim()
    $lines.Add("version: $ver")
    $lines.Add("ip: $ip (expected $($t.IP))")
    $lines.Add("mount: $mount")
    $lines.Add("ip_ok: $($ip -eq $t.IP)")
}
$lines | Set-Content $out -Encoding UTF8
