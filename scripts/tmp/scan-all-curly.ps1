$ErrorActionPreference = 'Stop'
$codes = @(0x201C,0x201D,0x2018,0x2019,0x2013,0x2014)
$roots = @('scripts\client','publish')
$badFiles = 0
Get-ChildItem -Path $roots -Recurse -Include *.ps1,*.bat,*.sh -File | ForEach-Object {
  $bytes = [IO.File]::ReadAllBytes($_.FullName)
  $bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
  $text = [Text.Encoding]::UTF8.GetString($bytes)
  $hitCount = 0
  $samples = New-Object System.Collections.Generic.List[string]
  for ($i=0; $i -lt $text.Length; $i++) {
    $c = [int][char]$text[$i]
    if ($codes -contains $c) {
      $hitCount++
      if ($samples.Count -lt 5) {
        $line = ($text.Substring(0,$i) -split "`n").Count
        $samples.Add(("U+{0:X4}@L{1}" -f $c, $line)) | Out-Null
      }
    }
  }
  if ($bom -or $hitCount -gt 0) {
    $badFiles++
    $rel = $_.FullName.Substring((Get-Location).Path.Length).TrimStart('\')
    Write-Host ("BAD {0} BOM={1} count={2} {3}" -f $rel, $bom, $hitCount, ($samples -join '; '))
  }
}
Write-Host ("TOTAL_BAD_FILES=$badFiles")
