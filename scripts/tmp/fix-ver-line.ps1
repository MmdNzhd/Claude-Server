Set-Location D:\Smart\Claude-Code-Server
$utf8 = New-Object System.Text.UTF8Encoding $false
$ver = (Get-Content scripts/client/windows/connect-version.txt -Raw).Trim()
$path = Resolve-Path 'scripts/client/windows/connect.ps1'
$t = [IO.File]::ReadAllText($path)
# fix doubled / broken ConnectVersion assignment
$t2 = [regex]::Replace($t, '(?m)^\$script:ConnectVersion(?:\$script:ConnectVersion)*\s*=\s*''20260720\.\d+''\s*$', "`$script:ConnectVersion = '$ver'")
# also fix if concatenated without newline junk
$t2 = [regex]::Replace($t2, '\$script:ConnectVersion\$script:ConnectVersion\s*=\s*''20260720\.\d+''', "`$script:ConnectVersion = '$ver'")
if ($t2 -eq $t -and $t -notmatch "(?m)^\`$script:ConnectVersion = '$([regex]::Escape($ver))'\s*$") {
  # force line replace around Alias
  $t2 = [regex]::Replace($t, '(?m)^(\$Alias\s*=\s*"[^"]+"\s*\r?\n).*$', "`$1`$script:ConnectVersion = '$ver'")
}
# verify single clean line
$m = [regex]::Matches($t2, '(?m)^\$script:ConnectVersion.*$')
Write-Host "matches=$($m.Count)"
foreach ($x in $m) { Write-Host ("LINE:[{0}]" -f $x.Value) }
if ($m.Count -ne 1 -or $m[0].Value -ne "`$script:ConnectVersion = '$ver'") {
  # last resort: read lines and fix
  $lines = [IO.File]::ReadAllLines($path)
  for ($i=0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match 'ConnectVersion') {
      if ($lines[$i] -match '\$script:ConnectVersion') {
        Write-Host ("fixing L{0}: {1}" -f ($i+1), $lines[$i])
        $lines[$i] = "`$script:ConnectVersion = '$ver'"
      }
    }
  }
  [IO.File]::WriteAllLines($path, $lines, $utf8)
} else {
  [IO.File]::WriteAllText($path, $t2, $utf8)
}
# parse
$tok=$null;$err=$null
$null=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tok,[ref]$err)
if ($err -and $err.Count) {
  Write-Host 'STILL BROKEN' -ForegroundColor Red
  $err | ForEach-Object { Write-Host $_.Message }
  Get-Content $path | Select-Object -Skip 92 -First 6 | ForEach-Object -Begin{$i=93}-Process{ Write-Host ("{0}|{1}" -f $i,$_); $i++ }
  exit 1
}
Write-Host "PARSE OK ConnectVersion=$ver" -ForegroundColor Green
Get-Content $path | Select-Object -Skip 92 -First 6 | ForEach-Object -Begin{$i=93}-Process{ Write-Host ("{0}|{1}" -f $i,$_); $i++ }

# Update verify: Clear-SessionMount ok with if ($StopEditor -and $EditorCmd
$gm = Get-Content scripts/client/git-mode.ps1 -Raw
if ($gm -match 'if \(\$StopEditor -and \$EditorCmd') { Write-Host 'OK StopEditor gate present' -ForegroundColor Green }
else { Write-Host 'WARN StopEditor gate pattern' -ForegroundColor Yellow }
