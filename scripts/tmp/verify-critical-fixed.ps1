# VERIFY Agent W7 — static P0 contracts (harsh, contract-accurate)
$ErrorActionPreference = 'Continue'
$here = $PSScriptRoot
$root = (Resolve-Path (Join-Path $here '..\..')).Path
if (-not (Test-Path (Join-Path $root 'scripts\client\windows\connect.ps1'))) {
  $root = (Get-Location).Path
}
$results = [ordered]@{}
$evidence = [ordered]@{}

function Add-Check([string]$name, [bool]$pass, [string]$ev) {
  if ($pass) { $results[$name] = 'PASS' } else { $results[$name] = 'FAIL' }
  $evidence[$name] = $ev
}
function Overall-Label([bool]$ok) {
  if ($ok) { return 'PASS' }
  return 'FAIL'
}

# 1) curly quotes
$connect = Join-Path $root 'scripts\client\windows\connect.ps1'
$bytes = [IO.File]::ReadAllBytes($connect)
$curlyHits = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt ($bytes.Length - 2); $i++) {
  if ($bytes[$i] -eq 0xE2 -and $bytes[$i+1] -eq 0x80) {
    $b2 = $bytes[$i+2]
    if ($b2 -eq 0x98 -or $b2 -eq 0x99 -or $b2 -eq 0x9C -or $b2 -eq 0x9D) {
      $prefix = [Text.Encoding]::UTF8.GetString($bytes, 0, $i)
      $line = ($prefix -split "`n").Count
      $uname = 'U+201?'
      if ($b2 -eq 0x98) { $uname = 'U+2018' }
      elseif ($b2 -eq 0x99) { $uname = 'U+2019' }
      elseif ($b2 -eq 0x9C) { $uname = 'U+201C' }
      elseif ($b2 -eq 0x9D) { $uname = 'U+201D' }
      [void]$curlyHits.Add(("byteOffset={0} line~{1} {2}" -f $i, $line, $uname))
    }
  }
}
$text = [IO.File]::ReadAllText($connect)
foreach ($code in @(0x2018,0x2019,0x201C,0x201D)) {
  $ch = [char]$code; $idx = 0; $guard = 0
  while (($idx = $text.IndexOf([string]$ch, $idx)) -ge 0) {
    $line = ($text.Substring(0, $idx) -split "`n").Count
    [void]$curlyHits.Add(("charIndex={0} line~{1} U+{2:X4}" -f $idx, $line, $code))
    $idx++; $guard++; if ($guard -gt 40) { break }
  }
}
$ev1 = 'no U+2018/2019/201C/201D in connect.ps1'
if ($curlyHits.Count -gt 0) { $ev1 = (($curlyHits | Select-Object -First 15) -join '; ') }
Add-Check 'connect.ps1_no_curly_quotes' ($curlyHits.Count -eq 0) $ev1

# 2) seq
$gmsh = Join-Path $root 'scripts\client\git-mode.sh'
$sh = [IO.File]::ReadAllText($gmsh)
$lines = $sh -split "`n"
$seq4 = New-Object System.Collections.Generic.List[string]
$seq12 = New-Object System.Collections.Generic.List[string]
for ($n = 0; $n -lt $lines.Length; $n++) {
  if ($lines[$n] -match 'seq\s+1\s+4\b') { [void]$seq4.Add(("L{0}: {1}" -f ($n+1), $lines[$n].Trim())) }
  if ($lines[$n] -match 'seq\s+1\s+12\b') { [void]$seq12.Add(("L{0}: {1}" -f ($n+1), $lines[$n].Trim())) }
}
Add-Check 'git-mode.sh_tunnel_wait_seq_1_12' (($seq4.Count -eq 0) -and ($seq12.Count -ge 1)) ("seq1_4=[{0}]; seq1_12=[{1}]" -f (($seq4 -join ' | '), ($seq12 -join ' | ')))

# 3) recover nested sshx
$recoverStart = -1
for ($n = 0; $n -lt $lines.Length; $n++) {
  if ($lines[$n] -match '^recover_mounts_if_needed\s*\(') { $recoverStart = $n; break }
}
$recoverPass = $false
$recoverEv = 'recover_mounts_if_needed not found'
if ($recoverStart -ge 0) {
  $depth = 0; $recoverEnd = $recoverStart
  for ($n = $recoverStart; $n -lt $lines.Length; $n++) {
    $l = $lines[$n]
    $depth += ([regex]::Matches($l, '\{')).Count
    $depth -= ([regex]::Matches($l, '\}')).Count
    $recoverEnd = $n
    if ($n -gt $recoverStart -and $depth -le 0) { break }
  }
  $nested = New-Object System.Collections.Generic.List[string]
  for ($n = $recoverStart; $n -le $recoverEnd; $n++) {
    $l = $lines[$n]
    if ($l -match 'sshx\s+"\$CM[^"]*\|\|.*sshx\s+"\$CM') { [void]$nested.Add(("L{0}: {1}" -f ($n+1), $l.Trim())) }
    $m = [regex]::Matches($l, 'sshx\s+"\$CM')
    if ($m.Count -ge 2) { [void]$nested.Add(("L{0}: multi-sshx-CM count={1}: {2}" -f ($n+1), $m.Count, $l.Trim())) }
    if ($l -match 'sshx\s+".*sshx\s+') { [void]$nested.Add(("L{0}: nested-sshx-in-string: {1}" -f ($n+1), $l.Trim())) }
  }
  $recoverPass = ($nested.Count -eq 0)
  if ($recoverPass) { $recoverEv = "recover_mounts_if_needed L{0}-L{1}: no nested sshx CM" -f ($recoverStart+1), ($recoverEnd+1) }
  else { $recoverEv = (($nested | Select-Object -Unique) -join ' || ') }
}
Add-Check 'recover_mounts_no_nested_sshx' $recoverPass $recoverEv

# 4) banner_miss: MUST NOT SoftFailCount=0 without ++ toward DROP
#    TUNNEL_SYNC banner_miss must ++ and have DROP budget
#    ENSURE banner_miss may reseed without ++; FAIL only if it zeros SoftFailCount
$gmps = Join-Path $root 'scripts\client\git-mode.ps1'
$ps = [IO.File]::ReadAllText($gmps)
$psLines = $ps -split "`n"
$bannerFails = New-Object System.Collections.Generic.List[string]
$bannerNotes = New-Object System.Collections.Generic.List[string]
for ($n = 0; $n -lt $psLines.Length; $n++) {
  if ($psLines[$n] -notmatch 'banner_miss') { continue }
  $start = [Math]::Max(0, $n - 6)
  $end = [Math]::Min($n + 14, $psLines.Length - 1)
  $increments = $false
  $hasDropBudget = $false
  $zeros = New-Object System.Collections.Generic.List[int]
  for ($k = $start; $k -le $end; $k++) {
    if ($psLines[$k] -match 'TunnelSoftFailCount\s*\+\+') { $increments = $true }
    if ($psLines[$k] -match 'TunnelSoftFailCount\s*-ge\s*6' -or $psLines[$k] -match 'banner_miss_tcp_open_budget') { $hasDropBudget = $true }
    if ($psLines[$k] -match 'TunnelSoftFailCount\s*=\s*0') { [void]$zeros.Add($k) }
  }
  $isEnsure = ($psLines[$n] -match 'ENSURE_TUNNEL')
  $isSync = ($psLines[$n] -match 'TUNNEL_SYNC' -or ($psLines[$n] -match 'soft_fail' -and -not $isEnsure))

  if ($isSync -or ($psLines[$n] -match 'TUNNEL_SYNC soft_fail.*banner_miss')) {
    if (-not $increments) {
      [void]$bannerFails.Add(("L{0}: TUNNEL_SYNC banner_miss missing SoftFailCount++ : {1}" -f ($n+1), $psLines[$n].Trim()))
    } elseif (-not $hasDropBudget) {
      [void]$bannerFails.Add(("L{0}: TUNNEL_SYNC banner_miss has ++ but no DROP budget (-ge 6 / _budget) : {1}" -f ($n+1), $psLines[$n].Trim()))
    } else {
      [void]$bannerNotes.Add(("L{0}: TUNNEL_SYNC OK ++ and DROP budget" -f ($n+1)))
    }
    # zero without being after DROP budget in window is FAIL
    foreach ($zk in $zeros) {
      $afterDrop = $false
      for ($j = $start; $j -le $zk; $j++) {
        if ($psLines[$j] -match 'banner_miss_tcp_open_budget' -or ($psLines[$j] -match 'TUNNEL_DROP' -and $psLines[$j] -match 'banner_miss')) {
          $afterDrop = $true
        }
      }
      if (-not $afterDrop -and -not $increments) {
        [void]$bannerFails.Add(("L{0}: SoftFailCount=0 on banner_miss without ++ : {1}" -f ($zk+1), $psLines[$zk].Trim()))
      }
    }
  }

  if ($isEnsure) {
    # FAIL if SoftFailCount reset to 0 in window (soft-success) without ++
    foreach ($zk in $zeros) {
      if (-not $increments) {
        [void]$bannerFails.Add(("L{0}: ENSURE banner_miss resets SoftFailCount=0 without ++ : {1}" -f ($zk+1), $psLines[$zk].Trim()))
      }
    }
    if ($zeros.Count -eq 0) {
      [void]$bannerNotes.Add(("L{0}: ENSURE banner_miss reseeds without SoftFailCount zero-reset" -f ($n+1)))
    }
  }
}

# Detect classic soft-success bug: banner_miss then SoftFailCount=0 then return true with no ++
for ($n = 0; $n -lt $psLines.Length; $n++) {
  if ($psLines[$n] -match 'reason=banner_miss_tcp_open' -and $psLines[$n] -notmatch 'budget') {
    $window = ($psLines[$n..([Math]::Min($n+6, $psLines.Length-1))] -join "`n")
    if ($window -match 'TunnelSoftFailCount\s*=\s*0' -and $window -notmatch 'TunnelSoftFailCount\s*\+\+' -and $window -match 'return\s+\$true') {
      [void]$bannerFails.Add(("L{0}: soft-success pattern (banner_miss + SoftFailCount=0 + return true, no ++)" -f ($n+1)))
    }
  }
}

$ev4 = 'banner_miss: sync ++ toward DROP; no SoftFailCount=0 soft-success'
if ($bannerFails.Count -gt 0) { $ev4 = (($bannerFails | Select-Object -Unique) -join ' || ') }
elseif ($bannerNotes.Count -gt 0) { $ev4 = (($bannerNotes | Select-Object -Unique) -join ' ; ') }
Add-Check 'git-mode.ps1_banner_miss_softfail' ($bannerFails.Count -eq 0) $ev4

# parse
$parseErr = $null; $tok = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($gmps, [ref]$tok, [ref]$parseErr)
$parsePass = -not ($parseErr -and $parseErr.Count -gt 0)
$parseEv = 'git-mode.ps1 Parser::ParseFile OK'
if (-not $parsePass) {
  $parseEv = (($parseErr | Select-Object -First 8 | ForEach-Object { "L{0}: {1}" -f $_.Extent.StartLineNumber, $_.Message }) -join ' || ')
}
Add-Check 'git-mode.ps1_parses' $parsePass $parseEv

# 5) cursor auth temp
$auth = Join-Path $root 'scripts\client\cursor-auth-laptop.ps1'
$at = [IO.File]::ReadAllText($auth)
$atLines = $at -split "`n"
$hasFn = [bool]($at -match 'function\s+Get-CursorAuthTempRoot\b')
$badRm = New-Object System.Collections.Generic.List[string]
for ($n = 0; $n -lt $atLines.Length; $n++) {
  $l = $atLines[$n]
  if ($l -match 'Remove-Item[^\r\n]*\$tmp[^\r\n]*-Recurse' -or $l -match 'Remove-Item[^\r\n]*-Recurse[^\r\n]*\$tmp') {
    [void]$badRm.Add(("L{0}: {1}" -f ($n+1), $l.Trim()))
  }
}
$fnLabel = 'NO'; if ($hasFn) { $fnLabel = 'YES' }
Add-Check 'cursor_auth_temp_root_safe' ($hasFn -and ($badRm.Count -eq 0)) ("Get-CursorAuthTempRoot={0}; bad_Remove-Item_tmp_Recurse=[{1}]" -f $fnLabel, ($badRm -join ' | '))

Write-Host '=== VERIFY-CRITICAL-FIXED ==='
foreach ($k in $results.Keys) {
  Write-Host ("CHECK {0}: {1}" -f $k, $results[$k])
  Write-Host ("  EVIDENCE: {0}" -f $evidence[$k])
}
$failCount = @($results.Values | Where-Object { $_ -eq 'FAIL' }).Count
$allPass = ($failCount -eq 0)
$staticLabel = Overall-Label $allPass
Write-Host ("STATIC_OVERALL: {0}" -f $staticLabel)
$outPath = Join-Path $here 'verify-critical-fixed.out.txt'
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('=== VERIFY-CRITICAL-FIXED ===')
foreach ($k in $results.Keys) {
  [void]$sb.AppendLine(("CHECK {0}: {1}" -f $k, $results[$k]))
  [void]$sb.AppendLine(("  EVIDENCE: {0}" -f $evidence[$k]))
}
[void]$sb.AppendLine(("STATIC_OVERALL: {0}" -f $staticLabel))
[IO.File]::WriteAllText($outPath, $sb.ToString())
# also emit JSON-ish key=value for report
$kvPath = Join-Path $here 'verify-critical-fixed.kv.txt'
$kv = New-Object System.Text.StringBuilder
foreach ($k in $results.Keys) { [void]$kv.AppendLine(("{0}={1}" -f $k, $results[$k])) }
[void]$kv.AppendLine(("STATIC_OVERALL={0}" -f $staticLabel))
[IO.File]::WriteAllText($kvPath, $kv.ToString())
if (-not $allPass) { exit 1 }
exit 0
