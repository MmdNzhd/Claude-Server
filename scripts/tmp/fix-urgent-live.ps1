#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-Location D:\Smart\Claude-Code-Server
$utf8 = New-Object System.Text.UTF8Encoding $false

# --- 1) Write-ConnectDecision AllowEmptyString ---
$uiPath = Resolve-Path 'scripts/client/connect-ui.ps1'
$ui = [IO.File]::ReadAllText($uiPath)
$oldDec = @'
function Write-ConnectDecision {
    param(
        [Parameter(Mandatory)][string]$What,
        [Parameter(Mandatory)][string]$Value,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'TRACE')][string]$Level = 'INFO'
    )
    Write-ConnectLog ("DECISION: {0}={1}" -f $What, $Value) $Level
}
'@
$newDec = @'
function Write-ConnectDecision {
    param(
        [Parameter(Mandatory)][string]$What,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value = '',
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'TRACE')][string]$Level = 'INFO'
    )
    if ($null -eq $Value) { $Value = '' }
    Write-ConnectLog ("DECISION: {0}={1}" -f $What, $Value) $Level
}
'@
if ($ui.Contains($oldDec)) {
  $ui = $ui.Replace($oldDec, $newDec)
  Write-Host 'OK Write-ConnectDecision AllowEmptyString' -ForegroundColor Green
} elseif ($ui -match 'AllowEmptyString') {
  Write-Host 'SKIP Decision already AllowEmptyString' -ForegroundColor Yellow
} else {
  Write-Host 'WARN Decision block exact match miss - regex' -ForegroundColor Yellow
  $ui2 = [regex]::Replace($ui, '(?s)function Write-ConnectDecision \{.*?^\}\s*(?=function )', ($newDec + "`r`n`r`n"), 1)
  if ($ui2 -eq $ui) { throw 'Decision replace failed' }
  $ui = $ui2
  Write-Host 'OK Decision via regex' -ForegroundColor Green
}

# --- 2) Status line: Write-Host only on change ---
$oldStat = @'
    $tunnel = if ($TunnelOk) { 'up' } else { 'down' }
    $ed = if ($EditorLabel) { $EditorLabel } elseif ($EditorOpen) { $EditorName } else { 'closed' }
    $line = ('    [{0} | git:{1} | tunnel:{2} | {3}]' -f $ProjectLabel, $GitLabel, $tunnel, $ed)
    Write-Host $line -ForegroundColor DarkCyan
    $statusKey = "$ProjectLabel|$GitLabel|$tunnel|$ed"
    if ($statusKey -ne $script:LastSessionStatusKey) {
        $script:LastSessionStatusKey = $statusKey
        Write-ConnectLog "STATUS: [$ProjectLabel | git:$GitLabel | tunnel:$tunnel | $ed]"
    }
'@
$newStat = @'
    $tunnel = if ($TunnelOk) { 'up' } else { 'down' }
    $ed = if ($EditorLabel) { $EditorLabel } elseif ($EditorOpen) { $EditorName } else { 'closed' }
    $line = ('    [{0} | git:{1} | tunnel:{2} | {3}]' -f $ProjectLabel, $GitLabel, $tunnel, $ed)
    $statusKey = "$ProjectLabel|$GitLabel|$tunnel|$ed"
    if ($statusKey -ne $script:LastSessionStatusKey) {
        $script:LastSessionStatusKey = $statusKey
        Write-Host $line -ForegroundColor DarkCyan
        Write-ConnectLog "STATUS: [$ProjectLabel | git:$GitLabel | tunnel:$tunnel | $ed]"
    }
'@
if ($ui.Contains($oldStat)) {
  $ui = $ui.Replace($oldStat, $newStat)
  Write-Host 'OK status line dedupe Write-Host' -ForegroundColor Green
} elseif ($ui -match '(?s)\$statusKey = .*?\r?\n\s*if \(\$statusKey -ne \$script:LastSessionStatusKey\) \{\r?\n\s*\$script:LastSessionStatusKey = \$statusKey\r?\n\s*Write-Host \$line') {
  Write-Host 'SKIP status already fixed' -ForegroundColor Yellow
} else {
  Write-Host 'WARN status exact miss' -ForegroundColor Yellow
  # try LF-only
  $oldStatLf = $oldStat -replace "`r`n","`n"
  $newStatLf = $newStat -replace "`r`n","`n"
  $uiLf = $ui -replace "`r`n","`n"
  if ($uiLf.Contains($oldStatLf)) {
    $ui = ($uiLf.Replace($oldStatLf, $newStatLf) -replace "`n","`r`n")
    Write-Host 'OK status via LF normalize' -ForegroundColor Green
  } else {
    throw 'status replace failed'
  }
}

[IO.File]::WriteAllText($uiPath, $ui, $utf8)

# --- 3) Clear-SessionMount: default skip editor stop ---
$gmPath = Resolve-Path 'scripts/client/git-mode.ps1'
$gm = [IO.File]::ReadAllText($gmPath)
# Find Clear-SessionMount and force skip unless -StopEditor
if ($gm -match 'function Clear-SessionMount') {
  # Ensure StopEditor opt-in exists
  if ($gm -notmatch 'Clear-SessionMount[\s\S]{0,400}\[switch\]\$StopEditor') {
    $gm2 = [regex]::Replace($gm, '(?s)(function Clear-SessionMount\s*\{[\s\S]*?param\([\s\S]*?)(\[switch\]\$SkipEditorStop,?)', '${1}[switch]$SkipEditorStop,`r`n        [switch]$StopEditor,', 1)
    # Change condition: stop only if StopEditor OR (not SkipEditorStop AND legacy) — simplest: stop only if -StopEditor
    $gm2 = [regex]::Replace($gm2, '(?s)(function Clear-SessionMount\s*\{[\s\S]*?)if \(-not \$SkipEditorStop -and \$EditorCmd -and \$Alias -and \$RemotePath\)', '${1}# Default: never close Cursor on mount clear (tunnel drop / crash). Opt-in -StopEditor only.`r`n    if ($StopEditor -and -not $SkipEditorStop -and $EditorCmd -and $Alias -and $RemotePath)', 1)
    if ($gm2 -eq $gm) {
      Write-Host 'WARN Clear-SessionMount regex partial' -ForegroundColor Yellow
      # dump snippet
      $idx = $gm.IndexOf('function Clear-SessionMount')
      Write-Host $gm.Substring($idx, [Math]::Min(700,$gm.Length-$idx))
    } else {
      $gm = $gm2
      [IO.File]::WriteAllText($gmPath, $gm, $utf8)
      Write-Host 'OK Clear-SessionMount StopEditor opt-in' -ForegroundColor Green
    }
  } else {
    Write-Host 'SKIP Clear-SessionMount already has StopEditor' -ForegroundColor Yellow
  }
}

# --- 4) connect.ps1 finally: SkipEditorStop ---
$winPath = Resolve-Path 'scripts/client/windows/connect.ps1'
$win = [IO.File]::ReadAllText($winPath)
$oldClear = 'Clear-SessionMount -ProjectId $go.Id -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path'
# Only the finally one without reason - careful
$win2 = $win.Replace(
  "Clear-SessionMount -ProjectId `$go.Id -EditorCmd `$EditorCmd -Alias `$Alias -RemotePath `$go.Path`r`n                Write-Host `"    Laptop folder restored.`"",
  "Clear-SessionMount -ProjectId `$go.Id -EditorCmd `$EditorCmd -Alias `$Alias -RemotePath `$go.Path -SkipEditorStop -Reason 'session_end'`r`n                Write-Host `"    Laptop folder restored.`""
)
if ($win2 -eq $win) {
  $win2 = $win.Replace(
    "Clear-SessionMount -ProjectId `$go.Id -EditorCmd `$EditorCmd -Alias `$Alias -RemotePath `$go.Path`n                Write-Host `"    Laptop folder restored.`"",
    "Clear-SessionMount -ProjectId `$go.Id -EditorCmd `$EditorCmd -Alias `$Alias -RemotePath `$go.Path -SkipEditorStop -Reason 'session_end'`n                Write-Host `"    Laptop folder restored.`""
  )
}
# user_quit - also skip editor stop (safer)
$win2 = $win2.Replace(
  "Clear-SessionMount -ProjectId `$go.Id -EditorCmd `$EditorCmd -Alias `$Alias -RemotePath `$go.Path -Reason 'user_quit'",
  "Clear-SessionMount -ProjectId `$go.Id -EditorCmd `$EditorCmd -Alias `$Alias -RemotePath `$go.Path -SkipEditorStop -Reason 'user_quit'"
)
if ($win2 -ne $win) {
  [IO.File]::WriteAllText($winPath, $win2, $utf8)
  Write-Host 'OK connect.ps1 Clear-SessionMount SkipEditorStop' -ForegroundColor Green
} else {
  Write-Host 'WARN connect.ps1 clear replace miss - check callers' -ForegroundColor Yellow
  Select-String -Path $winPath -Pattern 'Clear-SessionMount' | ForEach-Object { Write-Host ("{0}:{1}" -f $_.LineNumber, $_.Line.Trim()) }
}

# --- 5) ssh_username_fix empty: don't throw ---
$win = [IO.File]::ReadAllText($winPath)
if ($win -match "Write-ConnectDecision 'ssh_username_fix' \$fix") {
  $win = $win.Replace(
    "Write-ConnectDecision 'ssh_username_fix' `$fix",
    "Write-ConnectDecision 'ssh_username_fix' ([string]`$fix)"
  )
  [IO.File]::WriteAllText($winPath, $win, $utf8)
  Write-Host 'OK ssh_username_fix cast' -ForegroundColor Green
}

Write-Host 'Done urgent fixes.' -ForegroundColor Cyan
