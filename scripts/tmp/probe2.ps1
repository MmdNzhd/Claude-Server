$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$mac = Get-Content (Join-Path $Root 'scripts\client\git-mode.sh')
function Get-FunctionBody([string[]]$Lines, [string]$NamePattern) {
    $hit = $Lines | Select-String -Pattern $NamePattern | Select-Object -First 1
    if (-not $hit) { return $null }
    $i = $hit.LineNumber - 1
    $depth = 0; $end = $i
    for ($j = $i; $j -lt $Lines.Count; $j++) {
        $depth += ([regex]::Matches($Lines[$j], '\{')).Count
        $depth -= ([regex]::Matches($Lines[$j], '\}')).Count
        $end = $j
        if ($j -gt $i -and $depth -le 0) { break }
    }
    return ($Lines[$i..$end] -join "`n")
}
$wf = Get-FunctionBody $mac '^wait_for_tunnel_up\(\)'
Write-Host "WF_LEN=$($wf.Length)"
Write-Host ("seq12=" + ($wf -match 'seq\s+1\s+12'))
Write-Host ("le12=" + ($wf -match '-le\s+12'))
Write-Host ("ge12=" + ($wf -match '-ge\s+12'))
Write-Host ("seq14=" + ($wf -match 'seq\s+1\s+4'))
# Does -le 12 false-match inside wf?
if ($wf -match '-le\s+12') { Write-Host 'LE_MATCH'; $Matches[0] }
# recover
$rf = Get-FunctionBody $mac '^recover_mounts_if_needed\(\)'
$recoverLines = @($rf -split "`n" | Where-Object { $_ -match 'sshx' -and $_ -match 'recover' })
Write-Host "RECOVER_LINES=$($recoverLines.Count)"
foreach ($line in $recoverLines) {
  $c = ([regex]::Matches($line, '\bsshx\b')).Count
  Write-Host "sshx_count=$c :: $($line.Trim().Substring(0,[Math]::Min(100,$line.Trim().Length)))"
}
# editor
$conn = Join-Path $Root 'scripts\client\windows\connect.ps1'
$h = @(Select-String -LiteralPath $conn -Pattern 'EDITOR_SEEN_CLEAR reason=editor_closed phase=session_poll' -SimpleMatch)
Write-Host "EDITOR_HITS=$($h.Count)"
Select-String -LiteralPath $conn -Pattern 'EDITOR_SEEN_CLEAR' | ForEach-Object { Write-Host "L$($_.LineNumber): $($_.Line.Trim())" }
# mac banner next lines
$n = (Select-String -LiteralPath (Join-Path $Root 'scripts\client\git-mode.sh') -Pattern 'TUNNEL_SYNC soft_fail.*banner_miss_tcp_open')[0].LineNumber - 1
Write-Host 'MAC_BANNER_CTX:'
$mac[$n..($n+8)] | ForEach-Object { Write-Host $_ }
