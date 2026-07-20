Get-ChildItem scripts/client/tests -Filter *.ps1 | ForEach-Object {
  $fn = $_.Name
  $i = 0
  Get-Content $_.FullName | ForEach-Object {
    $i++
    $line = $_
    if ($line -match 'Assert\s*\(\s*\$true\b') {
      Write-Host ("{0}:{1}:{2}" -f $fn, $i, $line.Trim())
    }
  }
}
Write-Host 'DONE assert scan'
