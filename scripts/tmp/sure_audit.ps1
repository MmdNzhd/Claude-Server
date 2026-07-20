$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
$fail = New-Object System.Collections.Generic.List[string]
function Must([bool]$cond, [string]$msg) {
    if ($cond) { Write-Host "OK   $msg" }
    else { $script:fail.Add($msg) | Out-Null; Write-Host "FAIL $msg" }
}

$c = [IO.File]::ReadAllText("$root\scripts\client\windows\connect.ps1")
Must (-not ($c -match 'Read-Host')) 'connect.ps1 no Read-Host'
Must (($c.Split('Wait-ConnectExit').Length - 1) -ge 10) 'connect.ps1 Wait-ConnectExit'
Must (($c.Split('Write-ConnectDecision').Length - 1) -ge 15) 'connect.ps1 decisions'
Must (($c.Split('Read-ConnectPrompt').Length - 1) -ge 10) 'connect.ps1 prompts'

$ui = [IO.File]::ReadAllText("$root\scripts\client\connect-ui.ps1")
Must ($ui.Contains('function Wait-ConnectExit')) 'Wait-ConnectExit defined'
Must ($ui.Contains('function Read-ConnectPrompt')) 'Read-ConnectPrompt defined'
Must ($ui.Contains('Read-ConnectLogSyncWatermark')) 'watermark'
Must ($ui.Contains('Get-ConnectLogSyncTarget')) 'sync target fallback'
Must ($ui.Contains('ConnectLogLinesSinceSync -ge 1')) 'sync every line'
Must ($ui.Contains('Keep durable local')) 'keep local logs'

$u = [IO.File]::ReadAllText("$root\scripts\client\windows\connect-update.ps1")
Must ($u.Contains('SSH_STAGE')) 'update SSH stages'
Must ($u.Contains('incomplete_files')) 'update incomplete logged'
$lines = $u -split "`n"
$silent = 0
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*exit 0\s*$') {
        $from = [Math]::Max(0, $i - 6)
        $w = ($lines[$from..$i] -join "`n")
        if ($w -notmatch 'Write-UpdateFileLog') {
            $silent++
            Write-Host ("SILENT exit0 line {0}" -f ($i + 1))
        }
    }
}
Must ($silent -eq 0) ('update no silent exit0 silent=' + $silent)

$bat = [IO.File]::ReadAllText("$root\scripts\client\windows\connect.bat")
Must ($bat.Contains('BOOTSTRAP')) 'bat bootstrap log'

$mac = [IO.File]::ReadAllText("$root\scripts\client\mac\connect.sh")
Must (-not [regex]::IsMatch($mac, '(?m)^\s*read -rp ')) 'mac no raw read -rp'
Must (($mac.Split('connect_prompt').Length - 1) -ge 10) 'mac connect_prompt used'

$mui = [IO.File]::ReadAllText("$root\scripts\client\connect-ui.sh")
Must ($mui.Contains('connect_prompt()')) 'mac ui connect_prompt'
Must ($mui.Contains('sync-offset')) 'mac watermark'

foreach ($rel in @(
    'scripts\client\connect-ui.ps1',
    'scripts\client\windows\connect.ps1',
    'scripts\client\windows\connect-update.ps1',
    'scripts\client\git-mode.ps1',
    'scripts\client\editor-launch.ps1'
)) {
    $errs = $null
    $null = [System.Management.Automation.Language.Parser]::ParseInput(
        [IO.File]::ReadAllText("$root\$rel"), [ref]$null, [ref]$errs)
    Must (-not ($errs -and $errs.Count)) ("parse $rel")
}

. "$root\publish\Get-DeployCredentials.ps1"
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$remote = @'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
printf '%s\n' "$PW" | sudo -S -p '' bash -c '
echo LIVE_VER=$(cat /usr/local/share/claude-client/connect-version.txt)
B=/usr/local/share/claude-client
echo WAIT=$(grep -c Wait-ConnectExit $B/connect-ui.ps1)
echo PROMPT=$(grep -c Read-ConnectPrompt $B/connect-ui.ps1)
echo WATER=$(grep -c SyncWatermark $B/connect-ui.ps1)
echo STAGE=$(grep -c SSH_STAGE $B/connect-update.ps1)
echo INCOMPLETE=$(grep -c incomplete_files $B/connect-update.ps1)
echo BOOT=$(grep -c BOOTSTRAP $B/connect.bat)
'
'@
$remote = $remote.Replace('__PWB64__', $pwB64) -replace "`r", ''
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out = Join-Path $env:TEMP 'sure.out'
$p = Start-Process ssh -ArgumentList @(
    '-o', 'BatchMode=yes', '-o', 'ControlMaster=no', 'sepidz@192.168.250.70',
    ("echo $b64 | base64 -d | bash")
) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out + '.err')
[void]$p.WaitForExit(60000)
$live = (Get-Content $out -Raw)
Write-Host $live
Must ($live -match 'LIVE_VER=20260719\.9') 'live is 20260719.9'
Must ($live -match 'INCOMPLETE=[1-9]') 'live incomplete_files'
Must ($live -match 'STAGE=[1-9]') 'live SSH_STAGE'

if ($fail.Count -gt 0) {
    Write-Host ('NOT_SURE fail_count=' + $fail.Count)
    $fail | ForEach-Object { Write-Host (' - ' + $_) }
    exit 1
}
Write-Host 'SURE_ALL_CHECKS_PASSED'
