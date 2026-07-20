$out = Join-Path $PSScriptRoot 'server-audit.txt'
$sb = New-Object System.Text.StringBuilder
function Add([string]$s) { [void]$sb.AppendLine($s) }

Add '=== Server audit ==='
foreach ($t in @(
    @{L='Smart';S='smart@192.168.210.240';IP='192.168.210.240'},
    @{L='Sepidz';S='smart@192.168.250.70';IP='192.168.250.70'}
)) {
    Add "--- $($t.L) ($($t.S)) ---"
    $p = Start-Process -FilePath 'ssh' -ArgumentList @(
        '-o','BatchMode=yes','-o','ConnectTimeout=5','-o','ConnectionAttempts=1',$t.S,
        "ver=`$(tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt 2>/dev/null); ip=`$(grep -o '192.168.[0-9.]*' /usr/local/share/claude-client/connect.ps1 2>/dev/null | head -1); bash -n /usr/local/share/claude-client/mac/claude-mount.sh >/dev/null 2>&1 && m=OK || m=FAIL; echo version=`$ver; echo ip=`$ip; echo mount=`$m"
    ) -NoNewWindow -Wait -PassThru -RedirectStandardOutput (Join-Path $env:TEMP "audit-$($t.L).out") -RedirectStandardError (Join-Path $env:TEMP "audit-$($t.L).err")
    Add "ssh_exit=$($p.ExitCode)"
    $stdout = Get-Content (Join-Path $env:TEMP "audit-$($t.L).out") -ErrorAction SilentlyContinue
    if ($stdout) { $stdout | ForEach-Object { Add $_ } }
    $ipLine = $stdout | Where-Object { $_ -match '^ip=' } | Select-Object -First 1
    if ($ipLine) {
        $ip = $ipLine.Substring(3)
        Add "ip_ok=$($ip -eq $t.IP)"
    }
}
$sb.ToString() | Set-Content $out -Encoding UTF8
Write-Host "Wrote $out"
