$ErrorActionPreference='Stop'
function Replace-Exact {
    param([string]$Path, [string]$Old, [string]$New, [string]$Label)
    $raw = [IO.File]::ReadAllText($Path)
    $nl = if ($raw -match "`r`n") { "`r`n" } else { "`n" }
    $c = $raw -replace "`r`n", "`n" -replace "`r", "`n"
    $oldN = $Old -replace "`r`n", "`n" -replace "`r", "`n"
    $newN = $New -replace "`r`n", "`n" -replace "`r", "`n"
    if ($c.IndexOf($oldN) -lt 0) { throw "pattern missing: $Label" }
    $n=0;$i=0; while(($i=$c.IndexOf($oldN,$i)) -ge 0){$n++;$i+=$oldN.Length}
    if ($n -ne 1) { throw "expected 1 of $Label got $n" }
    $c2 = $c.Replace($oldN, $newN)
    if ($Path -match '\.sh$') { $c2 = $c2 -replace "`r`n","`n" }
    elseif ($nl -eq "`r`n") { $c2 = $c2 -replace "`n","`r`n" }
    [IO.File]::WriteAllText($Path, $c2)
    Write-Host "OK $Label"
}

$gm = (Resolve-Path 'scripts\client\git-mode.ps1').Path
# Replace the SshX probe line — match current single-connect read version
$c = ([IO.File]::ReadAllText($gm) -replace "`r`n","`n")
if ($c -notmatch 'read -r -t 2 line <&3') { throw 'expected current read probe' }
$c2 = [regex]::Replace($c,
    '\$r = SshX "timeout 3 bash -c ''exec 3<>/dev/tcp/127\.0\.0\.1/\$Port 2>/dev/null \|\| exit 1; IFS= read -r -t 2 line <&3 \|\| true; printf %s \\`"\$line\\`"'' 2>/dev/null" 2>\$null',
    'PLACEHOLDER')
# Simpler line-based
$lines = $c -split "`n"
$hit=0
for ($i=0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match 'SshX' -and $lines[$i] -match 'read -r -t 2 line') {
    $lines[$i] = '    $r = SshX "timeout 3 nc -w 2 127.0.0.1 $Port 2>/dev/null | head -1" 2>$null'
    $hit++
  }
}
if ($hit -ne 1) { throw "probe line hits=$hit" }
$out = ($lines -join "`n") -replace "`n","`r`n"
[IO.File]::WriteAllText($gm, $out)
Write-Host 'OK ps1 nc-only probe'

$sh = (Resolve-Path 'scripts\client\git-mode.sh').Path
Replace-Exact -Path $sh -Label 'sh-raw-nc' -Old @'
tunnel_fetch_banner_raw() {
    [ -n "${PORT:-}" ] || return 1
    # Single TCP connection — avoid /dev/tcp+nc (2 MaxStartups slots).
    sshx "timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/${PORT} 2>/dev/null || exit 1; IFS= read -r -t 2 line <&3 || true; printf %s \"\$line\"' 2>/dev/null" 2>/dev/null | tr -d '\r\n'
}
'@ -New @'
tunnel_fetch_banner_raw() {
    [ -n "${PORT:-}" ] || return 1
    # Single TCP connection (nc only). Old /dev/tcp+nc used 2 MaxStartups slots.
    sshx "timeout 3 nc -w 2 127.0.0.1 ${PORT} 2>/dev/null | head -1" 2>/dev/null | tr -d '\r\n'
}
'@

# Live test nc-only via python socket already works; test nc from server through laptop-exec? 
# Run from server using only nc in a file written without forbidden patterns
Write-Host 'DONE'
