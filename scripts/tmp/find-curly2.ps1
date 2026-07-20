$p = 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1'
$src = Get-Content $p -Raw
$m = [regex]::Matches($src, '[\u201C\u201D\u2018\u2019]')
Write-Output ("REGEX_MATCHES=" + $m.Count)
foreach ($x in $m) {
  $idx = $x.Index
  $before = $src.Substring(0, $idx)
  $line = ($before -split "`n").Count
  $ctxStart = [Math]::Max(0, $idx - 50)
  $ctx = $src.Substring($ctxStart, [Math]::Min(100, $src.Length - $ctxStart)) -replace "`r",'' -replace "`n",' | '
  $code = [int][char]$x.Value
  Write-Output ("L{0} idx={1} U+{2:X4} ctx=[{3}]" -f $line, $idx, $code, $ctx)
}
# byte scan for UTF-8 curly quotes
$bytes = [IO.File]::ReadAllBytes($p)
Write-Output ("FILE_BYTES=" + $bytes.Length)
Write-Output ("BOM=" + (($bytes[0..2] | ForEach-Object { $_.ToString('X2') }) -join ' '))
$patterns = @{
  'E2 80 9C'=@(0xE2,0x80,0x9C)
  'E2 80 9D'=@(0xE2,0x80,0x9D)
  'E2 80 98'=@(0xE2,0x80,0x98)
  'E2 80 99'=@(0xE2,0x80,0x99)
  'UTF16 LE 201C'=@(0x1C,0x20)
  'UTF16 LE 201D'=@(0x1D,0x20)
  'UTF16 LE 2018'=@(0x18,0x20)
  'UTF16 LE 2019'=@(0x19,0x20)
}
foreach ($name in $patterns.Keys) {
  $pat = $patterns[$name]
  $count = 0
  for ($i=0; $i -le $bytes.Length - $pat.Length; $i++) {
    $ok=$true
    for ($j=0; $j -lt $pat.Length; $j++) { if ($bytes[$i+$j] -ne $pat[$j]) { $ok=$false; break } }
    if ($ok) { $count++ }
  }
  if ($count -gt 0) { Write-Output ("BYTE_HIT $name count=$count") }
}
# also dump any char where -match would hit via char codes in Get-Content
$odd = @()
for ($i=0; $i -lt [Math]::Min($src.Length, 500000); $i++) {
  $c = [int][char]$src[$i]
  if ($c -in 0x201C,0x201D,0x2018,0x2019) { $odd += $i }
}
Write-Output ("CHAR_SCAN=" + $odd.Count)
