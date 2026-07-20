$patterns = @(
  'TEST-AGENT-*.md',
  'TEST-*-OUT.txt',
  'test-*-out.txt',
  'REVIEW-*.md',
  'FIX-AGENT-*.md'
)
$dir = 'scripts/tmp'
foreach ($p in $patterns) {
  Write-Output "=== PATTERN: $p ==="
  Get-ChildItem -Path $dir -Filter $p -File -ErrorAction SilentlyContinue |
    Sort-Object Name |
    ForEach-Object {
      $n = $_.Name
      $l = $_.Length
      $t = $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
      Write-Output "$n | $l | $t"
    }
}
