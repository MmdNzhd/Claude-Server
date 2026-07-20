param([string]$Path, [int]$Start, [int]$End)
$lines = Get-Content -LiteralPath $Path
for ($i = $Start - 1; $i -lt $End -and $i -lt $lines.Count; $i++) {
    '{0,5}|{1}' -f ($i + 1), $lines[$i]
}
