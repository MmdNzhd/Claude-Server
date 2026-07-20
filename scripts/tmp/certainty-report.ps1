$ErrorActionPreference = 'Continue'
$expect = '20260717.3'
$results = @()

function Add-Result([string]$Area, [bool]$Ok, [string]$Detail) {
    $script:results += [pscustomobject]@{ Area = $Area; OK = $Ok; Detail = $Detail }
    if ($Ok) { Write-Host "PASS  [$Area] $Detail" -ForegroundColor Green }
    else { Write-Host "FAIL  [$Area] $Detail" -ForegroundColor Red }
}

foreach ($item in @(
    @{ A = 'pack-smart'; P = "$env:USERPROFILE\Desktop\claude-publish\claude-code-client-20260717\windows" },
    @{ A = 'pack-sepidz'; P = "$env:USERPROFILE\Desktop\claude-publish\claude-code-sepidz-20260717\claude-code\windows" }
)) {
    $p = $item.P
    if (-not (Test-Path $p)) { Add-Result $item.A $false 'missing pack'; continue }
    $v = (Get-Content "$p\connect-version.txt" -Raw).Trim()
    $el = Get-Content "$p\editor-launch.ps1" -Raw
    $auth = Get-Content "$p\cursor-auth-laptop.ps1" -Raw
    $gm = Get-Content "$p\git-mode.ps1" -Raw
    $ok = ($v -eq $expect) -and ($el -match 'Default User') -and ($auth -match 'Get-CursorAuthTempRoot') -and ($gm -match 'Test-TunnelBannerIsWindows -Banner \$banner') -and ($el -match 'preserve_open_windows') -and ($el -notmatch 'pre_launch_agent_or_new_window')
    Add-Result $item.A $ok "ver=$v"
}

. "$env:USERPROFILE\Desktop\claude-publish\claude-code-client-20260717\windows\editor-launch.ps1"
$script:LaptopUser = 'NoSuchUser'
$savedUser = $env:USERNAME
$env:USERNAME = 'Administrator'
$cli = Ensure-EditorOnPath 'cursor'
$env:USERNAME = $savedUser
Add-Result 'cursor-admin-sim' ([bool]($cli -and (Test-Path $cli))) "$cli"

$pyPath = Join-Path $env:TEMP 'certainty-probe.py'
@'
import pathlib, paramiko, re, zipfile, io
KEY = pathlib.Path.home() / ".ssh" / "id_ed25519"
EXPECT = "20260717.3"

def probe(host, user):
    c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(host, username=user, key_filename=str(KEY), timeout=20, allow_agent=False, look_for_keys=False)
    cmd = r"""B=/usr/local/share/claude-client
echo version=$(tr -d '\r\n' < $B/connect-version.txt)
echo auth=$(grep -c Get-CursorAuthTempRoot $B/cursor-auth-laptop.ps1 || echo 0)
echo scan=$(grep -c 'Default User' $B/editor-launch.ps1 || echo 0)
echo tunnel=$(grep -c 'Test-TunnelBannerIsWindows -Banner \$banner' $B/git-mode.ps1 || echo 0)
echo force=$(grep -c pre_launch_agent_or_new_window $B/editor-launch.ps1 || echo 0)
echo diag=$(grep -c 'not found for this Windows user' $B/connect-diagnostic.ps1 || echo 0)
"""
    _, o, _ = c.exec_command(cmd, timeout=30)
    out = o.read().decode().strip(); c.close(); return out

for label, host, user in [("SEPIDZ","192.168.250.70","sepidz"),("SMART","192.168.210.240","smart")]:
    try:
        out = probe(host, user)
        ver = re.search(r"version=(\S+)", out).group(1)
        auth = int(re.search(r"auth=(\d+)", out).group(1))
        scan = int(re.search(r"scan=(\d+)", out).group(1))
        tunnel = int(re.search(r"tunnel=(\d+)", out).group(1))
        force = int(re.search(r"force=(\d+)", out).group(1))
        diag = int(re.search(r"diag=(\d+)", out).group(1))
        ok = (ver == EXPECT and auth >= 1 and scan >= 1 and tunnel >= 1 and force == 0 and diag >= 1)
        print(f"JUDGE|{label}|{'PASS' if ok else 'FAIL'}|ver={ver};auth={auth};scan={scan};tunnel={tunnel};force={force};diag={diag}")
    except Exception as e:
        print(f"JUDGE|{label}|FAIL|error={e}")

c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect("192.168.210.240", username="smart", key_filename=str(KEY), timeout=15, allow_agent=False, look_for_keys=False)
sftp = c.open_sftp()
try:
    with sftp.open("/home/smart/claude-client-bundle-deploy/bundle.zip", "rb") as f:
        data = f.read()
    z = zipfile.ZipFile(io.BytesIO(data))
    ver = z.read("connect-version.txt").decode().strip()
    el = z.read("editor-launch.ps1").decode("utf-8", "replace")
    ok = (ver == EXPECT and "Default User" in el and "Get-CursorAuthTempRoot" in z.read("cursor-auth-laptop.ps1").decode("utf-8","replace"))
    print(f"JUDGE|smart-pending-zip|{'PASS' if ok else 'FAIL'}|ver={ver};scan={('Default User' in el)}")
except Exception as e:
    print(f"JUDGE|smart-pending-zip|FAIL|error={e}")
finally:
    sftp.close(); c.close()
'@ | Set-Content -Path $pyPath -Encoding UTF8

python -u $pyPath | ForEach-Object {
    Write-Host $_
    if ($_ -match '^JUDGE\|([^|]+)\|(PASS|FAIL)\|(.+)$') {
        Add-Result $Matches[1] ($Matches[2] -eq 'PASS') $Matches[3]
    }
}

Write-Host ''
Write-Host '======== CERTAINTY SUMMARY ========' -ForegroundColor White
$results | Format-Table -AutoSize | Out-String | Write-Host
$smart = $results | Where-Object { $_.Area -eq 'SMART' } | Select-Object -First 1
$others = @($results | Where-Object { $_.Area -ne 'SMART' })
$othersOk = (@($others | Where-Object { -not $_.OK }).Count -eq 0)
$smartOk = ($smart -and $smart.OK)

if ($othersOk -and $smartOk) {
    Write-Host 'CERTAIN: ALL LIVE SYSTEMS OK' -ForegroundColor Green
    exit 0
}
if ($othersOk -and -not $smartOk) {
    Write-Host 'CERTAIN: packs+Sepidz+Cursor OK. Smart LIVE still old - run: bash ~/install-client-bundle-now.sh' -ForegroundColor Yellow
    exit 2
}
Write-Host 'NOT CERTAIN: see FAIL lines' -ForegroundColor Red
exit 1
