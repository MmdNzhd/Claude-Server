$src = Get-Content 'scripts\client\git-mode.ps1' | Where-Object { $_ -match 'printf %s' -and $_ -match 'SshX' } | Select-Object -First 1
Write-Host "SRC=$src"
# Show chars around line
$idx = $src.IndexOf('printf')
Write-Host ("AROUND=" + $src.Substring($idx, [Math]::Min(40, $src.Length-$idx)))
# Check for backtick
if ($src.Contains([char]96 + '$line')) { 'HAS_BACKTICK_DOLLAR' } else { 'NO_BACKTICK' }
# Also check sh side
$sh = Get-Content 'scripts\client\git-mode.sh' | Where-Object { $_ -match 'printf %s' } | Select-Object -First 1
Write-Host "SH=$sh"
# Live test the probe command on server via a simulated expansion
$Port = 21003
# Simulate what PS sends: expand $Port and `$line
$cmd = "timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/$Port 2>/dev/null || exit 1; IFS= read -r -t 2 line <&3 || true; printf %s `"$([char]36)line`"' 2>/dev/null"
# Better: build with backtick in a scriptblock
$sb = [scriptblock]::Create(@'
param($Port)
"timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/$Port 2>/dev/null || exit 1; IFS= read -r -t 2 line <&3 || true; printf %s \"`$line\"' 2>/dev/null"
'@)
$expanded = & $sb 21003
Write-Host "EXPANDED=$expanded"
if ($expanded -match '\$line' -and $expanded -notmatch 'SHOULD') { 'EXPAND_OK' } else { "EXPAND_BAD=$expanded" }
