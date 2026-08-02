# test-hard-utf8-mojibake-fleet.ps1
# HARD+: no L1/DEEP/BOM/display-mojibake in shipped client scripts;
# MCP write preserves UTF-8 + newlines; listen-wait loops >=20;
# Repair-WindowsMcpUtf8WriteNewline present; PowerShell parse of key scripts.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')

function Assert([bool]$Cond, [string]$Msg) {
    if (-not $Cond) { throw "ASSERT FAIL: $Msg" }
    Write-Host "  OK  $Msg" -ForegroundColor Green
}

Write-Host '=== HARD+: UTF-8 / mojibake / MCP write fleet ===' -ForegroundColor White

# L1 = UTF-8 emdash once round-tripped through cp1252
$L1 = [byte[]](0xC3, 0xA2, 0xE2, 0x82, 0xAC, 0xE2, 0x80, 0x9D)
$DEEP = [byte[]](0xC3, 0x83, 0xC2, 0xA2)
$BOM = [byte[]](0xEF, 0xBB, 0xBF)
# UTF-8 encoding of U+00E2 U+20AC (classic "a-circumflex + euro" display mojibake prefix)
$DisplayMoj = [byte[]](0xC3, 0xA2, 0xE2, 0x82, 0xAC)

function Test-BytesContain([byte[]]$Hay, [byte[]]$Needle) {
    if ($Needle.Length -eq 0 -or $Hay.Length -lt $Needle.Length) { return $false }
    for ($i = 0; $i -le $Hay.Length - $Needle.Length; $i++) {
        $ok = $true
        for ($j = 0; $j -lt $Needle.Length; $j++) {
            if ($Hay[$i + $j] -ne $Needle[$j]) { $ok = $false; break }
        }
        if ($ok) { return $true }
    }
    return $false
}

function Assert-CleanTextFile([string]$Path) {
    Assert (Test-Path -LiteralPath $Path) "exists $Path"
    $b = [IO.File]::ReadAllBytes($Path)
    $name = [IO.Path]::GetFileName($Path)
    Assert (-not (Test-BytesContain $b $BOM)) "no BOM $name"
    Assert (-not (Test-BytesContain $b $L1)) "no L1-emdash $name"
    Assert (-not (Test-BytesContain $b $DEEP)) "no DEEP-starter $name"
    Assert (-not (Test-BytesContain $b $DisplayMoj)) "no display-mojibake $name"
    $t = [Text.Encoding]::UTF8.GetString($b)
    Assert ($t -notmatch [char]0x009D) "no U+009D $name"
    if ($Path -match '\.ps1$') {
        $errs = $null; $tok = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tok, [ref]$errs)
        Assert (-not $errs -or $errs.Count -eq 0) "parse OK $name"
    }
}

$keys = @(
    (Get-ClientFile 'windows\windows-mcp-laptop.ps1'),
    (Get-ClientFile 'windows\connect.ps1'),
    (Get-ClientFile 'windows\connect-update.ps1'),
    (Get-ClientFile 'windows\connect.bat'),
    (Get-ClientFile 'windows\connect-boot.ps1'),
    (Get-ClientFile 'windows\connect-hide-console.ps1'),
    (Get-ClientFile 'connect-ui.ps1'),
    (Get-ClientFile 'editor-launch.ps1'),
    (Get-ClientFile 'git-mode.ps1'),
    (Get-ClientFile 'git-mode.sh'),
    (Get-ClientFile 'mac\connect.sh')
)

$seen = @{}
foreach ($p in $keys) {
    if (-not (Test-Path -LiteralPath $p)) { continue }
    $full = [IO.Path]::GetFullPath($p)
    if ($seen.ContainsKey($full)) { continue }
    $seen[$full] = $true
    Assert-CleanTextFile $p
}

$clientRoot = Split-Path (Get-ClientFile 'windows\connect.ps1') -Parent | Split-Path -Parent
$shipGlobs = @(
    (Join-Path $clientRoot 'windows\*.ps1'),
    (Join-Path $clientRoot 'windows\*.bat'),
    (Join-Path $clientRoot 'windows\*.vbs'),
    (Join-Path $clientRoot 'mac\*.sh'),
    (Join-Path $clientRoot 'connect-ui.ps1'),
    (Join-Path $clientRoot 'connect-ui.sh'),
    (Join-Path $clientRoot 'editor-launch.ps1'),
    (Join-Path $clientRoot 'editor-launch.sh'),
    (Join-Path $clientRoot 'git-mode.ps1'),
    (Join-Path $clientRoot 'git-mode.sh')
)
$shipFiles = @()
foreach ($g in $shipGlobs) {
    $shipFiles += @(Get-Item -Path $g -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer })
}
Assert ($shipFiles.Count -ge 20) ("ship scan file count >=20 (got $($shipFiles.Count))")
$shipBad = @()
foreach ($f in $shipFiles) {
    $b = [IO.File]::ReadAllBytes($f.FullName)
    $hits = @()
    if (Test-BytesContain $b $BOM) { $hits += 'BOM' }
    if (Test-BytesContain $b $L1) { $hits += 'L1' }
    if (Test-BytesContain $b $DEEP) { $hits += 'DEEP' }
    if (Test-BytesContain $b $DisplayMoj) { $hits += 'display_mojibake' }
    $t = [Text.Encoding]::UTF8.GetString($b)
    if ($t.Contains([char]0x009D)) { $hits += 'U009D' }
    if ($hits.Count -gt 0) { $shipBad += ("{0}:{1}" -f $f.Name, ($hits -join ',')) }
}
Assert ($shipBad.Count -eq 0) ("ship scan clean (bad=$($shipBad.Count): $($shipBad -join '; '))")
Write-Host ("  OK  ship scan clean ($($shipFiles.Count) files)") -ForegroundColor Green

$mcp = Get-ClientFile 'windows\windows-mcp-laptop.ps1'
$mcpText = [IO.File]::ReadAllText($mcp, [Text.UTF8Encoding]::new($false))
Assert ($mcpText -match 'Repair-WindowsMcpUtf8WriteNewline') 'Repair-WindowsMcpUtf8WriteNewline present'
Assert ($mcpText -match "newline=''") 'newline='''' patch string present'
$listenLoops = [regex]::Matches($mcpText, 'for \(\$i = 0; \$i -lt (\d+)') | ForEach-Object { [int]$_.Groups[1].Value }
Assert ($listenLoops.Count -ge 2) ("listen wait loops >=2 (got $($listenLoops.Count))")
Assert (($listenLoops | Where-Object { $_ -ge 20 }).Count -ge 2) ("listen wait loops >=20 x2 (got $($listenLoops -join ','))")
Assert ($mcpText -notmatch 'for \(\$i = 0; \$i -lt 8\)') 'no stale listen wait lt 8'

. $mcp
$svc = Join-Path $env:APPDATA 'uv\tools\windows-mcp\Lib\site-packages\windows_mcp\filesystem\service.py'
Assert (Test-Path -LiteralPath $svc) 'windows-mcp service.py installed'
$svcText = [IO.File]::ReadAllText($svc)
Assert ($svcText -match "newline\s*=\s*''") 'installed service.py has newline='''''

$py = Join-Path $env:APPDATA 'uv\tools\windows-mcp\Scripts\python.exe'
Assert (Test-Path -LiteralPath $py) 'windows-mcp python exists'
$tmp = Join-Path $env:TEMP ("cc-utf8-hard-" + [guid]::NewGuid().ToString('N') + '.txt')
$appDataEsc = $env:APPDATA.Replace('\', '\\')
$tmpEsc = $tmp.Replace('\', '\\')
$code = @"
import sys
sys.path.insert(0, r'$appDataEsc\\uv\\tools\\windows-mcp\\Lib\\site-packages')
from windows_mcp.filesystem.service import write_file
p = r'$tmpEsc'
write_file(p, 'سلام\nline2\r\nline3\n')
b = open(p, 'rb').read()
assert b'\r\r\n' not in b, b
assert 'سلام'.encode('utf-8') in b, b
assert b == 'سلام\nline2\r\nline3\n'.encode('utf-8'), b
print('WRITE_OK')
"@
$out = & $py -c $code 2>&1 | Out-String
Assert ($out -match 'WRITE_OK') "MCP write Persian+CRLF exact ($out)"
Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue

[void](Repair-WindowsMcpUtf8WriteNewline)
$svcText2 = [IO.File]::ReadAllText($svc)
Assert ($svcText2 -match "newline\s*=\s*''") 'newline patch still present after re-repair'

$l0 = [Text.Encoding]::UTF8.GetBytes([char]0x2014)
$moj = [Text.Encoding]::GetEncoding(1252).GetString($l0)
$l1 = [Text.Encoding]::UTF8.GetBytes($moj)
Assert (Test-BytesContain $l1 $L1) 'L1 pattern equals known signature'

$env:WINDOWS_MCP_ENSURE_QUIET = '1'
$sw = [Diagnostics.Stopwatch]::StartNew()
$reOk = $false
try { $reOk = [bool](Restart-WindowsMcpServer) } catch { $reOk = $false }
$sw.Stop()
Assert $reOk ("Restart-WindowsMcpServer returns true (elapsed $([math]::Round($sw.Elapsed.TotalSeconds,1))s)")
Assert ($sw.Elapsed.TotalSeconds -lt 35) ("Restart bounded <35s (got $([math]::Round($sw.Elapsed.TotalSeconds,1))s)")
Assert ([bool](Test-WindowsMcpListening)) 'listening after Restart depth check'

Write-Host 'HARD+ UTF-8 / mojibake / MCP: PASS' -ForegroundColor Green
exit 0
