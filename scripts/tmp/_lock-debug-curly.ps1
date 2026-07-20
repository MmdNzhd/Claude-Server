$ErrorActionPreference = 'Stop'
$rel = 'scripts/client/windows/connect.ps1'
$src = Get-Content -LiteralPath $rel -Raw
Write-Output ("len=" + $src.Length)
$m = [regex]::Matches($src, '[\u201C\u201D\u2018\u2019]')
Write-Output ("regex_hits=" + $m.Count)
foreach ($x in $m) {
  $before = $src.Substring(0, $x.Index)
  $line = ($before -split "`n").Count
  Write-Output ("L$line pos=$($x.Index) char=U+{0:X4} val='$($x.Value)'" -f [int][char]$x.Value)
}
# Also byte-scan UTF8
$bytes = [IO.File]::ReadAllBytes((Resolve-Path $rel))
$utf8 = [Text.Encoding]::UTF8.GetString($bytes)
$m2 = [regex]::Matches($utf8, '[\u201C\u201D\u2018\u2019]')
Write-Output ("utf8_regex_hits=" + $m2.Count)
# Show Get-Content encoding default
Write-Output ("PSVersion=" + $PSVersionTable.PSVersion)
# Check if -notmatch fails
$ok = ($src -notmatch '[\u201C\u201D\u2018\u2019]')
Write-Output ("notmatch_ok=$ok")
