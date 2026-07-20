param([string]$Path, [string]$Pattern)
$items = @()
if (Test-Path -LiteralPath $Path -PathType Container) {
  $items = Get-ChildItem -LiteralPath $Path -Recurse -Include *.ps1,*.sh -File
} else {
  $items = Get-Item -LiteralPath $Path
}
foreach ($f in $items) {
  Select-String -LiteralPath $f.FullName -Pattern $Pattern -ErrorAction SilentlyContinue |
    Select-Object -First 80 | ForEach-Object {
      $rel = $f.FullName
      if ($rel -match 'scripts\\client\\(.+)$') { $rel = 'scripts/client/' + ($Matches[1] -replace '\\','/') }
      $t = $_.Line.Trim()
      if ($t.Length -gt 140) { $t = $t.Substring(0,140) }
      '{0}:{1}:{2}' -f $rel, $_.LineNumber, $t
    }
}
