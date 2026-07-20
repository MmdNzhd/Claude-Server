$ErrorActionPreference = 'Continue'
$roots = @(
  "$env:USERPROFILE\Desktop",
  "$env:USERPROFILE\Downloads",
  "$env:USERPROFILE\Downloads\Telegram Desktop",
  "$env:TEMP",
  "D:\temp"
)
Write-Output '=== recent connect logs ==='
foreach ($r in $roots) {
  if (-not (Test-Path $r)) { continue }
  Get-ChildItem $r -Filter '*connect*.log' -File -EA SilentlyContinue |
    Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-5) } |
    Sort-Object LastWriteTime -Descending |
    ForEach-Object {
      $hits = Select-String -Path $_.FullName -Pattern 'hosseinm|h\.mohammadi|22005|SERVER_USER|VERDICT_|SESSION_STATUS|CURSOR_NOT|ERROR' -EA SilentlyContinue |
        Select-Object -First 3
      $isH = $false
      if (Select-String -Path $_.FullName -Pattern 'hosseinm|h\.mohammadi|22005' -Quiet -EA SilentlyContinue) { $isH = $true }
      "{0}`t{1}`t{2}`thosseinm={3}" -f $_.LastWriteTime.ToString('s'), $_.Length, $_.FullName, $isH
    }
}
