$ErrorActionPreference = 'Stop'
$path = (Resolve-Path 'scripts\client\windows\connect.ps1').Path
$utf8 = New-Object System.Text.UTF8Encoding $false
$t = [IO.File]::ReadAllText($path, $utf8)
$origLen = $t.Length

$map = @{
  ([char]0x2018) = "'"
  ([char]0x2019) = "'"
  ([char]0x201C) = '"'
  ([char]0x201D) = '"'
  ([char]0x2013) = '-'
  ([char]0x2014) = '-'
  ([char]0x2026) = '...'
  ([char]0x2192) = '->'
  ([char]0x2190) = '<-'
  ([char]0x00A0) = ' '
}

$sb = New-Object System.Text.StringBuilder ($t.Length + 64)
$replaced = 0
foreach ($ch in $t.ToCharArray()) {
  if ($map.ContainsKey($ch)) {
    [void]$sb.Append([string]$map[$ch])
    $replaced++
  } else {
    [void]$sb.Append($ch)
  }
}
$t2 = $sb.ToString()
$tmp = $path + '.tmpfix'
[IO.File]::WriteAllText($tmp, $t2, $utf8)
# Replace via Move with overwrite
[IO.File]::Copy($tmp, $path, $true)
[IO.File]::Delete($tmp)
Write-Host ("replaced=$replaced oldlen=$origLen newlen=$($t2.Length)")

$srcUtf8 = [IO.File]::ReadAllText($path, $utf8)
$pat = '[\u201C\u201D\u2018\u2019]'
Write-Host ("utf8_curly=" + [bool]($srcUtf8 -match $pat))
$srcGc = Get-Content $path -Raw
Write-Host ("gc_curly=" + [bool]($srcGc -match $pat))
if ($srcGc -match $pat) {
  $m = [regex]::Match($srcGc, $pat)
  $ctx = $srcGc.Substring([Math]::Max(0,$m.Index-50), 100) -replace "[\r\n]",' '
  Write-Host ("still U+{0:X4} ctx={1}" -f [int][char]$m.Value, $ctx)
}

$errs = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errs)
Write-Host ("parse_errs=" + $(if ($errs) { $errs.Count } else { 0 }))
if ($errs) { $errs | Select-Object -First 8 | ForEach-Object { Write-Host $_.ToString() } }

$odd = New-Object 'System.Collections.Generic.HashSet[int]'
foreach ($ch in $srcUtf8.ToCharArray()) {
  $code = [int]$ch
  if ($code -gt 127) { [void]$odd.Add($code) }
}
Write-Host ("unique_non_ascii=" + (($odd | Sort-Object | ForEach-Object { 'U+{0:X4}' -f $_ }) -join ','))
