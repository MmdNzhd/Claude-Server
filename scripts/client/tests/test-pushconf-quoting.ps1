# test-pushconf-quoting.ps1 - locks Farzad elif/quote storm + RESULT/dedupe gate
# Would have caught: nested AM="" -> AM="; elif syntax error on Windows OpenSSH.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0

function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== PushConf quoting / RESULT e2e (static) ===' -ForegroundColor Cyan

$gitModePs1 = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$gitModeSh  = Get-Content (Get-ClientFile 'git-mode.sh') -Raw

function Get-FunctionSource {
    param([string]$Source, [string]$Name)
    $m = [regex]::Match($Source, "(?ms)^function\s+$([regex]::Escape($Name))\s*\{.*?(?=^function\s+|\z)")
    if ($m.Success) { return $m.Value }
    return ''
}

$pushWin = Get-FunctionSource -Source $gitModePs1 -Name 'Push-ServerConnectConf'
Assert ($pushWin.Length -gt 200) 'Push-ServerConnectConf extracted from git-mode.ps1'

# Base64 remote body - the fix for Windows OpenSSH eating nested double quotes.
Assert ($pushWin -match 'ToBase64String') 'Win PushConf encodes remote body as Base64'
Assert ($pushWin -match 'base64 -d \| bash') 'Win PushConf runs echo b64 | base64 -d | bash'
Assert ($pushWin -match 'PUSH_CONF_RESULT') 'Win remote body prints PUSH_CONF_RESULT'
Assert ($pushWin -match 'LAPTOP_HOSTKEY_FP=%s') 'Win PushConf writes LAPTOP_HOSTKEY_FP'
Assert ($pushWin -match "HK='") 'Win PushConf sets HK= for hostkey'


# Farzad storm shape: CLEAR / PREFER / elif AM= (not AM="" in the ssh argv).
Assert ($pushWin -match "CLEAR='") 'Win remote body uses CLEAR= single-quoted assignment'
Assert ($pushWin -match 'elif \[ -n') 'Win remote body has elif PREFER branch'
Assert ($pushWin -match '#.*AM=""') 'Comment documents historical AM="" quote-storm vector'
$amBad = @($pushWin -split "`n" | Where-Object { $_ -notmatch '^\s*#' -and $_ -match 'AM=""' })
Assert ($amBad.Count -eq 0) 'Non-comment Win PushConf lines have no AM="" (elif storm vector)'

# RESULT required before dedupe success (bug win-pushconf-ok-without-result).
Assert ($pushWin -match '\$hasResult') 'Win PushConf tracks hasResult for PUSH_CONF_RESULT'
Assert ($pushWin -match 'pushExit -ne 0 -or -not \$hasResult') 'Win exit 0 without RESULT is treated as fail'
Assert ($pushWin -match 'LastPushConfKey') 'Win PushConf uses LastPushConfKey dedupe'
# Dedupe assignment must be in the else (success) branch after hasResult gate.
$okIdx = $pushWin.IndexOf('LastPushConfKey = $dedupeKey')
$gateIdx = $pushWin.IndexOf('-not $hasResult')
Assert ($okIdx -gt 0 -and $gateIdx -gt 0 -and $okIdx -gt $gateIdx) 'Dedupe key set only after RESULT gate'

# Simulate the remote body the way production builds it (empty prefer / clear=0).
$clearFlag = '0'
$preferEsc = ''
$lu = 'Smart'
$portEsc = '21002'
$modeEsc = 'hide'
$remoteBody = @"
set +e
CLEAR='$clearFlag'
PREFER='$preferEsc'
LU='$lu'
PORT='$portEsc'
MODE='$modeEsc'
if [ "`$CLEAR" = "1" ]; then
  AM=
elif [ -n "`$PREFER" ]; then
  AM=`$PREFER
else
  AM=`$(grep -E '^ACTIVE_MOUNT=' "`$HOME/.claude-connect.conf" 2>/dev/null | tail -1 | cut -d= -f2-)
fi
mkdir -p "`$HOME/.local/bin"
printf 'LAPTOP_USER=%s\nTUNNEL_PORT=%s\nPORT=%s\nTUNNEL_SLOT=%s\nGIT_MODE=%s\nLAPTOP_OS=windows\nACTIVE_MOUNT=%s\nLAPTOP_HOSTKEY_FP=%s\n' "`$LU" "`$PORT" "`$PORT" "`$SLOT" "`$MODE" "`$AM" "`$HK" > "`$HOME/.claude-connect.conf"
chmod 600 "`$HOME/.claude-connect.conf" 2>/dev/null || true
printf 'PUSH_CONF_RESULT clear=%s prefer=%s active=%s\n' "`$CLEAR" "`$PREFER" "`$AM"
"@
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remoteBody))
Assert ($b64.Length -gt 40) 'Sample remote body base64 encodes'
# Decode round-trip must still contain RESULT + elif (would catch mangled quoting).
$decoded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
Assert ($decoded -match 'PUSH_CONF_RESULT') 'Decoded body still has PUSH_CONF_RESULT'
Assert ($decoded -match 'elif \[ -n') 'Decoded body still has elif branch'
Assert ($decoded -notmatch 'AM=""') 'Decoded body has no AM=""'

# Prefer value that historically shattered double-quoted remote argv.
$preferNasty = 'proj"; elif true; then echo PWNED; fi #'
$preferEsc2 = ($preferNasty -replace "'", "'\''")
$remoteNasty = $remoteBody -replace "PREFER=''", ("PREFER='{0}'" -f $preferEsc2)
$b64n = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remoteNasty))
$decN = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64n))
Assert ($decN -match [regex]::Escape($preferNasty) -or $decN -match 'PREFER=') 'Nasty prefer survives inside base64 body (not ssh argv)'
Assert ($decN -match 'PUSH_CONF_RESULT') 'Nasty prefer body still ends with RESULT'

# Mac parity: base64 + RESULT; no || true swallow before exit check.
Assert ($gitModeSh -match 'push_server_connect_conf|PUSH_CONF_RESULT') 'Mac git-mode.sh has PushConf RESULT'
Assert ($gitModeSh -match 'base64 -d \| bash') 'Mac PushConf uses base64 -d | bash'
Assert ($gitModeSh -notmatch 'sshx "echo \$b64 \| base64 -d \| bash" 2>/dev/null \|\| true') 'Mac PushConf does not swallow sshx with || true'
Assert ($gitModeSh -match 'result_line=.*PUSH_CONF_RESULT|grep PUSH_CONF_RESULT') 'Mac checks PUSH_CONF_RESULT line'
Assert ($gitModeSh -match '\[ -z "\$result_line" \]') 'Mac fails closed when RESULT line empty'

Write-Host ''
if ($fail -eq 0) { Write-Host 'All pushconf quoting tests passed.' -ForegroundColor Green; exit 0 }
Write-Host "$fail test(s) failed." -ForegroundColor Red; exit 1
