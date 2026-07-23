$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false
$cp = (Resolve-Path 'scripts\client\windows\connect.ps1').Path
$t = [IO.File]::ReadAllText($cp)
$chars = @([char]0x2018,[char]0x2019,[char]0x201C,[char]0x201D,[char]0x2013,[char]0x2014,[char]0x2026,[char]0x00A0)
foreach ($ch in $chars) {
  $c = ([regex]::Matches($t, [regex]::Escape([string]$ch))).Count
  if ($c -gt 0) { Write-Host ("char U+{0:X4} count={1}" -f [int]$ch, $c) }
}
# also scan for any char > 127 that's not tab/newline
$odd = New-Object 'System.Collections.Generic.HashSet[int]'
foreach ($ch in $t.ToCharArray()) {
  $code = [int]$ch
  if ($code -gt 127) { [void]$odd.Add($code) }
}
Write-Host ("unique_non_ascii=" + (($odd | Sort-Object | ForEach-Object { 'U+{0:X4}' -f $_ }) -join ','))
# show contexts for each non-ascii
foreach ($code in ($odd | Sort-Object)) {
  $ch = [char]$code
  $idx = $t.IndexOf($ch)
  if ($idx -ge 0) {
    $s = $t.Substring([Math]::Max(0,$idx-50), [Math]::Min(120, $t.Length-[Math]::Max(0,$idx-50))) -replace "`r|`n",' | '
    Write-Host ("U+{0:X4}: {1}" -f $code, $s)
  }
}
# Replace all smart punctuation
$t2 = $t
$t2 = $t2.Replace([char]0x2018,"'").Replace([char]0x2019,"'")
$t2 = $t2.Replace([char]0x201C,'"').Replace([char]0x201D,'"')
$t2 = $t2.Replace([char]0x2013,'-').Replace([char]0x2014,'-')
$t2 = $t2.Replace([char]0x2026,'...')
$t2 = $t2.Replace([char]0x00A0,' ')
# also arrow-like unicode if present
$t2 = $t2.Replace([char]0x2192,'->').Replace([char]0x2190,'<-')
if ($t2 -ne $t) {
  [IO.File]::WriteAllText($cp, $t2, $utf8)
  Write-Host 'CONNECT_PS1_SANITIZED'
} else { Write-Host 'CONNECT_PS1_NO_CHANGE' }

# Re-test the specific assert
$src = [IO.File]::ReadAllText($cp)
$ok = $src -notmatch '[\u201C\u201D\u2018\u2019]'
Write-Host ("assert_no_curly=$ok")
# if still fail, show match
if (-not $ok) {
  $m = [regex]::Match($src, '[\u201C\u201D\u2018\u2019]')
  Write-Host ("still_match U+{0:X4} at {1}" -f [int][char]$m.Value, $m.Index)
}
