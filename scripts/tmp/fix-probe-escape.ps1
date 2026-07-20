$ErrorActionPreference='Stop'
$gm='scripts\client\git-mode.ps1'
$raw=[IO.File]::ReadAllText((Resolve-Path $gm))
$nl= if($raw -match "`r`n"){"`r`n"}else{"`n"}
$c=$raw -replace "`r`n","`n" -replace "`r","`n"
$old = '$r = SshX "timeout 3 bash -c ''exec 3<>/dev/tcp/127.0.0.1/$Port 2>/dev/null || exit 1; IFS= read -r -t 2 line <&3 || true; printf %s \"\$line\"'' 2>/dev/null" 2>$null'
# Use backtick-dollar for PowerShell escape
$new = @'
    $r = SshX "timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/$Port 2>/dev/null || exit 1; IFS= read -r -t 2 line <&3 || true; printf %s \"`$line\"' 2>/dev/null" 2>$null
'@
# Find line containing printf %s and replace that whole line
$lines = $c -split "`n"
$found=0
for ($i=0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match 'printf %s' -and $lines[$i] -match 'Get-TunnelBanner|SshX' -or ($lines[$i] -match 'printf %s \\"')) {
    if ($lines[$i] -match 'SshX' -and $lines[$i] -match 'read -r -t 2 line') {
      Write-Host "OLD: $($lines[$i])"
      $lines[$i] = '    $r = SshX "timeout 3 bash -c ''exec 3<>/dev/tcp/127.0.0.1/$Port 2>/dev/null || exit 1; IFS= read -r -t 2 line <&3 || true; printf %s \"`$line\"'' 2>/dev/null" 2>$null'
      # Wait - mixing quotes wrong. Build carefully:
      $lines[$i] = '    $r = SshX "timeout 3 bash -c ''exec 3<>/dev/tcp/127.0.0.1/$Port 2>/dev/null || exit 1; IFS= read -r -t 2 line <&3 || true; printf %s \"' + '`$line' + '\""'' 2>/dev/null" 2>$null'
      $found++
    }
  }
}
if ($found -ne 1) { throw "expected 1 probe line, found $found" }

# Simpler: direct string replace of the broken escape
$c2 = $c.Replace('printf %s \"\$line\"', 'printf %s \"`$line\"')
if ($c2 -eq $c) {
  # try without escape variants
  if ($c -match 'printf %s') { 
    Select-String -InputObject $c -Pattern 'printf %s.{0,20}' -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { "MATCH=[$($_.Value)]" }
  }
  throw 'escape replace failed'
}
if ($nl -eq "`r`n") { $c2 = $c2 -replace "`n","`r`n" }
[IO.File]::WriteAllText((Resolve-Path $gm), $c2)
Write-Host 'OK escaped `$line'

# Verify: expand as PowerShell would
$Port=21003
$line='SHOULD_NOT_APPEAR'
$expanded = Invoke-Expression ('"' + ((Get-Content $gm | Where-Object { $_ -match 'printf %s' -and $_ -match 'SshX' } | Select-Object -First 1) -replace '^\s+\$r = SshX ','' -replace ' 2>\$null$','') + '"')
# Actually simpler check: the source must contain backtick before $line
$src = Get-Content $gm | Where-Object { $_ -match 'printf %s' -and $_ -match 'SshX' } | Select-Object -First 1
Write-Host "SRC=$src"
if ($src -notmatch '`$line') { throw 'backtick-dollar missing in source' }
Write-Host 'ESCAPE_OK'
