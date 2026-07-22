$t = Get-Content -Raw publish/sepidz-deploy.local.ps1
Write-Host ("len=" + $t.Length)
Write-Host ("lines=" + ($t -split "`n").Count)
foreach ($line in ($t -split "`n")) {
  $l = $line.TrimEnd()
  if ($l -match 'SshUser|ServerIp') { Write-Host $l }
  elseif ($l -match 'Password') {
    if ($l -match "'") { Write-Host '$SepidzSudoPassword = *** (single-quoted)' }
    elseif ($l -match '"') { Write-Host '$SepidzSudoPassword = *** (double-quoted)' }
    else { Write-Host ('PASSWORD_LINE_STYLE_UNKNOWN len=' + $l.Length) }
  }
  elseif ($l -match '^#') { Write-Host $l }
}
$m = [regex]::Match($t, "(?m)^\s*\$SepidzSudoPassword\s*=\s*'([^']*)'")
Write-Host ("regex_single_ok=" + $m.Success + " capt_len=" + $m.Groups[1].Value.Length)
$m2 = [regex]::Match($t, '(?m)^\s*\$SepidzSudoPassword\s*=\s*"([^"]*)"')
Write-Host ("regex_double_ok=" + $m2.Success + " capt_len=" + $m2.Groups[1].Value.Length)
# hex of first password line chars around =
foreach ($line in ($t -split "`n")) {
  if ($line -match 'Password') {
    $bytes = [Text.Encoding]::UTF8.GetBytes($line.Substring(0, [Math]::Min(40, $line.Length)))
    Write-Host ("prefix_hex=" + ([BitConverter]::ToString($bytes)))
    break
  }
}
