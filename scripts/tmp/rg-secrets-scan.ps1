Set-Location 'D:\Smart\Claude-Code-Server'
$patterns = @(
  'sepidz@Admin',
  'Mohammad123',
  "SudoPassword\s*=\s*'[^']+'",
  'SQLSERVER_PASSWORD',
  'CLAUDE_CODE_OAUTH_TOKEN=',
  'BEGIN (RSA|OPENSSH) PRIVATE KEY',
  'sk-ant-oat01-[A-Za-z0-9_-]{20,}'
)
$roots = @('publish','scripts\server\commands')
foreach ($root in $roots) {
  Write-Output ("=== SCAN $root ===")
  Get-ChildItem $root -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -match '\.(ps1|sh|bat|py|md|txt|example)$' -or $_.Name -eq 'claude-client-deploy' } |
    ForEach-Object {
      $rel = $_.FullName.Substring((Get-Location).Path.Length+1)
      $text = [IO.File]::ReadAllText($_.FullName)
      foreach ($pat in $patterns) {
        if ($text -match $pat) {
          $hits = Select-String -LiteralPath $_.FullName -Pattern $pat -AllMatches -ErrorAction SilentlyContinue
          foreach ($h in $hits) {
            $line = $h.Line.Trim()
            if ($line.Length -gt 140) { $line = $line.Substring(0,140) + '...' }
            Write-Output ("{0}:{1}: [{2}] {3}" -f $rel, $h.LineNumber, $pat, $line)
          }
        }
      }
    }
}
