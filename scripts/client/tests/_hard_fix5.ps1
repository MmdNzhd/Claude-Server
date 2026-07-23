$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$path = Get-ClientFile 'windows\connect.ps1'
$src = Get-Content $path -Raw
$pat = '[\u201C\u201D\u2018\u2019]'
Write-Host ("Get-Content match=" + [bool]($src -match $pat))
Write-Host ("len=" + $src.Length)
$ms = [regex]::Matches($src, $pat)
Write-Host ("count=" + $ms.Count)
foreach ($x in $ms) {
  $ctx = $src.Substring([Math]::Max(0,$x.Index-40), [Math]::Min(80, $src.Length - [Math]::Max(0,$x.Index-40)))
  $ctx = $ctx -replace "[\r\n]", ' '
  Write-Host ("idx={0} U+{1:X4} ctx={2}" -f $x.Index, [int][char]$x.Value, $ctx)
}
$bytes = [IO.File]::ReadAllBytes($path)
Write-Host ("file_bytes=" + $bytes.Length)
Write-Host ("bom=" + ($bytes[0..2] -join ','))
$utf8Curly = 0
for ($i=0; $i -lt $bytes.Length-2; $i++) {
  if ($bytes[$i] -eq 0xE2 -and $bytes[$i+1] -eq 0x80 -and ($bytes[$i+2] -in @(0x98,0x99,0x9C,0x9D))) {
    Write-Host ("utf8_curly_at=$i b2=$($bytes[$i+2])")
    $utf8Curly++
    if ($utf8Curly -ge 5) { break }
  }
}
Write-Host ("utf8_curly_total_scanned_first5done=$utf8Curly")

# Decode as UTF8 vs Default to see difference
$utf8 = [Text.Encoding]::UTF8.GetString($bytes)
$def = [Text.Encoding]::Default.GetString($bytes)
Write-Host ("utf8_curly_match=" + [bool]($utf8 -match $pat))
Write-Host ("default_curly_match=" + [bool]($def -match $pat))

# Fix mojibake / arrows / weird chars in connect.ps1 comments
$t = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
$orig = $t
# Replace arrow
$t = $t.Replace([string][char]0x2192, '->')
$t = $t.Replace([string][char]0x2190, '<-')
# Replace common mojibake fragments for arrows/quotes in comments
# Pattern seen: A~A and similar from corrupted UTF-8
$t = $t -replace 'A~A.', '->'
$t = $t -replace '[^\x09\x0A\x0D\x20-\x7E]', {
  param($m)
  $c = [int][char]$m.Value
  switch ($c) {
    0x00A0 { ' ' }
    0x00B6 { '' }  # pilcrow junk
    0x00C2 { '' }
    0x00C3 { '' }
    0x02DC { '' }
    default {
      if ($c -gt 127) { '' } else { $m.Value }
    }
  }
}
# Simpler: strip all non-ASCII printable to ASCII-safe
$sb = New-Object System.Text.StringBuilder
foreach ($ch in $t.ToCharArray()) {
  $code = [int]$ch
  if ($code -eq 9 -or $code -eq 10 -or $code -eq 13 -or ($code -ge 32 -and $code -le 126)) {
    [void]$sb.Append($ch)
  } else {
    # map known
    if ($code -eq 0x2192) { [void]$sb.Append('->') }
    elseif ($code -eq 0x2018 -or $code -eq 0x2019) { [void]$sb.Append("'") }
    elseif ($code -eq 0x201C -or $code -eq 0x201D) { [void]$sb.Append('"') }
    elseif ($code -eq 0x2013 -or $code -eq 0x2014) { [void]$sb.Append('-') }
    elseif ($code -eq 0x2026) { [void]$sb.Append('...') }
    else { [void]$sb.Append('') }
  }
}
$t2 = $sb.ToString()
$enc = New-Object System.Text.UTF8Encoding $false
[IO.File]::WriteAllText($path, $t2, $enc)
Write-Host ("CONNECT_STRIPPED changed=" + ($t2 -ne $orig) + " newlen=" + $t2.Length)

$src2 = Get-Content $path -Raw
Write-Host ("after_match=" + [bool]($src2 -match $pat))
$odd = New-Object 'System.Collections.Generic.HashSet[int]'
foreach ($ch in $src2.ToCharArray()) {
  $code = [int]$ch
  if ($code -gt 127) { [void]$odd.Add($code) }
}
Write-Host ("unique_non_ascii=" + (($odd | Sort-Object | ForEach-Object { 'U+{0:X4}' -f $_ }) -join ','))
