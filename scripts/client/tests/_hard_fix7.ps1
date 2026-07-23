$ErrorActionPreference = 'Stop'
$path = (Resolve-Path 'scripts\client\windows\connect.ps1').Path
$utf8 = New-Object System.Text.UTF8Encoding $false
$t = [IO.File]::ReadAllText($path, $utf8)

# Show contexts for remaining non-ascii
foreach ($code in @(0x00B6, 0x00C2, 0x00C3, 0x02DC)) {
  $ch = [char]$code
  $idx = 0
  $n = 0
  while (($idx = $t.IndexOf($ch, $idx)) -ge 0 -and $n -lt 3) {
    $ctx = $t.Substring([Math]::Max(0,$idx-60), [Math]::Min(140, $t.Length-[Math]::Max(0,$idx-60))) -replace "[\r\n]",' | '
    Write-Host ("U+{0:X4}@{1}: {2}" -f $code, $idx, $ctx)
    $idx++; $n++
  }
}

# Fix known mojibake comment fragments only (ASCII-safe)
$replacements = @(
  @{ Old = "never for Persian/other printable non-ASCII (A`u00C2`u00A0`u00C3`u02DC`u00B6 on Q)"; New = "never for Persian/other printable non-ASCII (arrow on Q)" }
)

# Broader: replace any run of those junk chars in comments with '->'
$t2 = [regex]::Replace($t, '[\u00C2\u00A0\u00C3\u02DC\u00B6]+', '->')
# Also collapse weird 'A->A->' patterns if created
$t2 = $t2 -replace 'A->A->', '->'
$t2 = $t2 -replace '\(A-> on Q\)', '(arrow glyph on Q)'
$t2 = $t2 -replace '\(-> on Q\)', '(arrow glyph on Q)'

if ($t2 -ne $t) {
  $tmp = $path + '.tmpfix'
  [IO.File]::WriteAllText($tmp, $t2, $utf8)
  [IO.File]::Copy($tmp, $path, $true)
  [IO.File]::Delete($tmp)
  Write-Host 'MOJIBAKE_FIXED'
} else { Write-Host 'NO_MOJIBAKE_CHANGE' }

$t3 = [IO.File]::ReadAllText($path, $utf8)
$odd = New-Object 'System.Collections.Generic.HashSet[int]'
foreach ($ch in $t3.ToCharArray()) { if ([int]$ch -gt 127) { [void]$odd.Add([int]$ch) } }
Write-Host ("unique_non_ascii=" + (($odd | Sort-Object | ForEach-Object { 'U+{0:X4}' -f $_ }) -join ','))
$errs=$null
$null=[System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$null,[ref]$errs)
Write-Host ("parse_errs=" + $(if($errs){$errs.Count}else{0}))
Write-Host ("gc_curly=" + [bool]((Get-Content $path -Raw) -match '[\u201C\u201D\u2018\u2019]'))
