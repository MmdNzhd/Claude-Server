$g = Get-Content scripts/client/git-mode.ps1 -Raw
Write-Host ("lt6=" + [bool]($g -match 'TunnelSoftFailCount\s*-lt\s*6'))
Write-Host ("lt6_literal=" + [bool](Select-String -LiteralPath scripts/client/git-mode.ps1 -Pattern 'TunnelSoftFailCount -lt 6' -SimpleMatch -Quiet))
$hit = Select-String -LiteralPath scripts/client/git-mode.ps1 -Pattern 'SoftFailCount'
$hit | Select-Object -First 15 | ForEach-Object { Write-Host ("L$($_.LineNumber): $($_.Line.Trim())") }
Write-Host '--- ensure ---'
$e = [regex]::Match($g, '(?s)function Ensure-SessionTunnel\s*\{.{0,3500}')
Write-Host ("ensure_len=" + $e.Value.Length)
Write-Host ("ensure_sole=" + [bool]($e.Value -match 'banner_miss_tcp_open[\s\S]{0,200}return\s*\$true'))
$idx = $e.Value.IndexOf('banner_miss')
Write-Host ("banner_idx=" + $idx)
if ($idx -ge 0) {
  $start = [Math]::Max(0, $idx - 40)
  Write-Host $e.Value.Substring($start, [Math]::Min(280, $e.Value.Length - $start))
}
Write-Host '--- soft after ---'
$soft = [regex]::Match($g, '(?s)TunnelSoftFailCount\+\+.*?TunnelSoftFailCount\s*-lt\s*6.*?\{.*?return\s*\$true.*?\}(.{0,900})')
Write-Host ("soft_ok=" + $soft.Success)
if ($soft.Success) {
  Write-Host 'AFTER:'
  Write-Host $soft.Groups[1].Value.Substring(0, [Math]::Min(400, $soft.Groups[1].Value.Length))
  Write-Host ("budgetHard DROP=" + ($soft.Groups[1].Value -match 'TUNNEL_DROP'))
  Write-Host ("budgetHard false=" + ($soft.Groups[1].Value -match 'return\s*\$false'))
}
Write-Host '--- banner sync ---'
$wsb = [regex]::Match($g, '(?s)TUNNEL_SYNC soft_fail[^\n]*reason=banner_miss_tcp_open(.{0,500})')
Write-Host $wsb.Value
Write-Host '--- editor ---'
$c = Get-Content scripts/client/windows/connect.ps1 -Raw
Write-Host ("elseClear1=" + [regex]::IsMatch($c, '(?s)-not\s+\$windowOpen[\s\S]{0,250}EditorSeenOpen\s*=\s*\$false'))
Write-Host ("elseClear2=" + [regex]::IsMatch($c, '(?s)\$windowOpen[\s\S]{0,350}EditorSeenOpen\s*=\s*\$false'))
Write-Host ("elseClear3=" + [regex]::IsMatch($c, '(?s)else\s*\{\s*\$editorOpened\s*=\s*\$false\s*[\r\n\s;]*\$script:EditorSeenOpen\s*=\s*\$false'))
Write-Host ("elseClear4=" + [regex]::IsMatch($c, '(?s)onFolderNow[\s\S]{0,400}EditorSeenOpen\s*=\s*\$false[\s\S]{0,80}windowOpen'))
# Find EditorSeenOpen = $false contexts
Select-String -LiteralPath scripts/client/windows/connect.ps1 -Pattern 'EditorSeenOpen\s*=\s*\$false' | ForEach-Object {
  Write-Host ("CLEAR L$($_.LineNumber): $($_.Line.Trim())")
}
