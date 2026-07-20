#Requires -Version 5.1
<#
.SYNOPSIS
  Parse/syntax-check all client PowerShell scripts + key bash helpers.
  Exit 1 if any parse error. Writes TEST-PARSE-OUT.txt and TEST-AGENT-PARSE.md.
#>
$ErrorActionPreference = 'Continue'
$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not (Test-Path (Join-Path $Root 'scripts\client'))) {
  $Root = (Get-Location).Path
}
Set-Location $Root

$OutTxt = Join-Path $Root 'scripts\tmp\TEST-PARSE-OUT.txt'
$OutMd  = Join-Path $Root 'scripts\tmp\TEST-AGENT-PARSE.md'
$lines = New-Object System.Collections.Generic.List[string]
$failCount = 0
$okCount = 0
$skipCount = 0
$results = New-Object System.Collections.Generic.List[object]

function Add-Line([string]$s) {
  $script:lines.Add($s) | Out-Null
  Write-Host $s
}

Add-Line "=== TEST-PARSE-ALL-CLIENT ==="
Add-Line ("Root: " + $Root)
Add-Line ("When: " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Add-Line ""

$ps1Files = New-Object System.Collections.Generic.List[string]

$winDir = Join-Path $Root 'scripts\client\windows'
if (Test-Path $winDir) {
  Get-ChildItem -Path $winDir -Filter '*.ps1' -File | ForEach-Object {
    $ps1Files.Add($_.FullName) | Out-Null
  }
}

$clientDir = Join-Path $Root 'scripts\client'
if (Test-Path $clientDir) {
  Get-ChildItem -Path $clientDir -Filter '*.ps1' -File | ForEach-Object {
    $ps1Files.Add($_.FullName) | Out-Null
  }
}

$pubDir = Join-Path $Root 'publish'
if (Test-Path $pubDir) {
  Get-ChildItem -Path $pubDir -Filter '*.ps1' -File | ForEach-Object {
    if ($_.Name -like '*local.ps1') {
      $script:skipCount++
      Add-Line ("SKIP (secrets): publish/" + $_.Name)
      return
    }
    $ps1Files.Add($_.FullName) | Out-Null
  }
}

$ps1Sorted = @($ps1Files | Sort-Object -Unique)

Add-Line ""
Add-Line ("--- PowerShell ParseFile (" + $ps1Sorted.Count + " files) ---")
Add-Line ""

foreach ($full in $ps1Sorted) {
  $rel = $full.Substring($Root.Length).TrimStart('\', '/')
  $tokens = $null
  $errs = $null
  $null = [System.Management.Automation.Language.Parser]::ParseFile($full, [ref]$tokens, [ref]$errs)
  if ($null -eq $errs) { $errs = @() }
  if ($errs.Count -gt 0) {
    $script:failCount++
    Add-Line ("FAIL  " + $rel)
    foreach ($e in $errs) {
      $msg = "  L{0}:C{1}  {2}" -f $e.Extent.StartLineNumber, $e.Extent.StartColumnNumber, $e.Message
      Add-Line $msg
    }
    $detParts = @($errs | ForEach-Object { $_.Message })
    $results.Add([pscustomobject]@{ Kind='ps1'; Path=$rel; Ok=$false; Detail=($detParts -join '; ') }) | Out-Null
  } else {
    $script:okCount++
    Add-Line ("OK    " + $rel)
    $results.Add([pscustomobject]@{ Kind='ps1'; Path=$rel; Ok=$true; Detail='' }) | Out-Null
  }
}

Add-Line ""
Add-Line "--- Bash -n (key scripts) ---"
Add-Line ""

$bashExe = 'C:\Program Files\Git\bin\bash.exe'
$bashScripts = @(
  'scripts\client\git-mode.sh',
  'scripts\client\mac\connect.sh',
  'scripts\client\mac\connect-update.sh'
)

if (-not (Test-Path $bashExe)) {
  Add-Line ("SKIP  Git bash not found at: " + $bashExe)
  Add-Line "      (bash -n not run)"
  foreach ($relWin in $bashScripts) {
    $results.Add([pscustomobject]@{ Kind='bash'; Path=($relWin.Replace('\','/')); Ok=$null; Detail='Git bash missing' }) | Out-Null
    $script:skipCount++
  }
} else {
  Add-Line ("Bash: " + $bashExe)
  foreach ($relWin in $bashScripts) {
    $full = Join-Path $Root $relWin
    $rel = $relWin.Replace('\', '/')
    if (-not (Test-Path $full)) {
      Add-Line ("MISS  " + $rel)
      $results.Add([pscustomobject]@{ Kind='bash'; Path=$rel; Ok=$false; Detail='file not found' }) | Out-Null
      $script:failCount++
      continue
    }
    $bashPath = $full -replace '\\', '/'
    if ($bashPath -match '^([A-Za-z]):') {
      $drive = $Matches[1].ToLower()
      $bashPath = '/' + $drive + ($bashPath.Substring(2))
    }
    $out = & $bashExe -n $bashPath 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0) {
      $script:failCount++
      Add-Line ("FAIL  " + $rel + " (exit " + $code + ")")
      if ($out) {
        foreach ($o in @($out)) { Add-Line ("  " + $o) }
      }
      $results.Add([pscustomobject]@{ Kind='bash'; Path=$rel; Ok=$false; Detail=([string]$out) }) | Out-Null
    } else {
      $script:okCount++
      Add-Line ("OK    " + $rel)
      $results.Add([pscustomobject]@{ Kind='bash'; Path=$rel; Ok=$true; Detail='' }) | Out-Null
    }
  }
}

Add-Line ""
Add-Line "=== SUMMARY ==="
Add-Line ("OK:   " + $okCount)
Add-Line ("FAIL: " + $failCount)
Add-Line ("SKIP: " + $skipCount)
if ($failCount -gt 0) { $verdict = 'HARD FAIL' } else { $verdict = 'PASS' }
Add-Line ("Verdict: " + $verdict)

$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllLines($OutTxt, $lines, $utf8)

$md = New-Object System.Collections.Generic.List[string]
$md.Add('# TEST-AGENT-PARSE') | Out-Null
$md.Add('') | Out-Null
$md.Add('Agent J - Parse/syntax all client PowerShell + key bash.') | Out-Null
$md.Add('') | Out-Null
$md.Add('| Metric | Value |') | Out-Null
$md.Add('|--------|-------|') | Out-Null
$md.Add("| When | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') |") | Out-Null
$md.Add("| Root | $Root |") | Out-Null
$md.Add("| OK | $okCount |") | Out-Null
$md.Add("| FAIL | $failCount |") | Out-Null
$md.Add("| SKIP | $skipCount |") | Out-Null
$md.Add("| Verdict | **$verdict** |") | Out-Null
$md.Add('') | Out-Null
$md.Add('## Results') | Out-Null
$md.Add('') | Out-Null
$md.Add('| Kind | Path | Status | Detail |') | Out-Null
$md.Add('|------|------|--------|--------|') | Out-Null
foreach ($r in $results) {
  if ($null -eq $r.Ok) { $st = 'SKIP' }
  elseif ($r.Ok) { $st = 'OK' }
  else { $st = 'FAIL' }
  $det = [string]$r.Detail
  if ($det.Length -gt 120) { $det = $det.Substring(0, 117) + '...' }
  $det = $det -replace '\|', '/' -replace "`r?`n", ' '
  $md.Add("| $($r.Kind) | $($r.Path) | $st | $det |") | Out-Null
}
$md.Add('') | Out-Null
$md.Add('Full log: `scripts/tmp/TEST-PARSE-OUT.txt`') | Out-Null
$md.Add('') | Out-Null
if ($failCount -gt 0) {
  $md.Add('## Failures (must fix)') | Out-Null
  $md.Add('') | Out-Null
  foreach ($r in $results) {
    if ($r.Ok -eq $false) {
      $md.Add("- **$($r.Path)**: $($r.Detail)") | Out-Null
    }
  }
  $md.Add('') | Out-Null
}

[System.IO.File]::WriteAllLines($OutMd, $md, $utf8)

Write-Host ""
Write-Host ("Wrote: " + $OutTxt)
Write-Host ("Wrote: " + $OutMd)

if ($failCount -gt 0) {
  exit 1
}
exit 0
