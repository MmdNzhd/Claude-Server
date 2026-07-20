#Requires -Version 5.1
# test-security-contracts.ps1 - Security static HARD suite (wave2 Agent O)
# Exit 1 if ANY check FAILs. No deploy. Run from repo root.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not (Test-Path (Join-Path $RepoRoot 'CLAUDE.md'))) {
    $RepoRoot = (Get-Location).Path
}
Set-Location $RepoRoot

$failCount = 0
$results = New-Object System.Collections.Generic.List[string]

function Add-Check {
    param([int]$Num, [string]$Name, [bool]$Ok, [string]$Detail)
    $st = if ($Ok) { 'PASS' } else { 'FAIL' }
    if (-not $Ok) { $script:failCount++ }
    $line = "CHECK$Num|$st|$Name|$Detail"
    $script:results.Add($line)
    $color = if ($Ok) { 'Green' } else { 'Red' }
    Write-Host ("[{0}] CHECK {1}: {2} - {3}" -f $st, $Num, $Name, $Detail) -ForegroundColor $color
}

function Read-Rel([string]$Rel) {
    $p = Join-Path $RepoRoot $Rel
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    return [IO.File]::ReadAllText($p)
}

Write-Host ''
Write-Host '=== Security static HARD suite (Agent O) ===' -ForegroundColor Cyan
Write-Host ("Repo: {0}" -f $RepoRoot)
Write-Host ''

# --- CHECK 1: no hardcoded password / sepidz@Admin fallback ---
$cred = Read-Rel 'publish/Get-DeployCredentials.ps1'
$bundles = Read-Rel 'publish/deploy-client-bundles.ps1'
$c1Ok = $true
$c1d = New-Object System.Collections.Generic.List[string]

if ($null -eq $cred) {
    $c1Ok = $false
    $c1d.Add('Get-DeployCredentials.ps1 missing')
} else {
    if ($cred -match 'sepidz@Admin') {
        $c1Ok = $false
        $c1d.Add('Get-DeployCredentials.ps1 contains sepidz@Admin')
    }
    if ($cred -match "return\s+'sepidz@Admin'") {
        $c1Ok = $false
        $c1d.Add('Get-DeployCredentials returns sepidz@Admin fallback')
    }
    if ($cred -notmatch 'No hardcoded fallback is allowed') {
        $c1Ok = $false
        $c1d.Add('missing explicit no-hardcoded-fallback throw text')
    }
    if ($cred -notmatch 'throw') {
        $c1Ok = $false
        $c1d.Add('Get-DeployCredentials does not throw when password missing')
    }
}

if ($null -eq $bundles) {
    $c1Ok = $false
    $c1d.Add('deploy-client-bundles.ps1 missing')
} else {
    if ($bundles -match 'sepidz@Admin') {
        $c1Ok = $false
        $c1d.Add('deploy-client-bundles.ps1 contains sepidz@Admin')
    }
    if ($bundles -match "sudoPw\s*=\s*'sepidz@Admin'") {
        $c1Ok = $false
        $c1d.Add('deploy-client-bundles hardcoded sudoPw sepidz@Admin')
    }
    # fallback literal assign covered by sepidz@Admin / sudoPw='...' checks above
}

if ($c1Ok) { $c1d.Add('no hardcoded password; no sepidz@Admin missing-file fallback') }
Add-Check 1 'deploy credentials no hardcoded/sepidz@Admin fallback' $c1Ok ($c1d -join '; ')

# --- CHECK 2: add-user SQL password placeholder only ---
$addUser = Read-Rel 'scripts/server/commands/add-user.sh'
$c2Ok = $true
$c2d = ''
if ($null -eq $addUser) {
    $c2Ok = $false
    $c2d = 'add-user.sh missing'
} else {
    $m = [regex]::Match($addUser, '"SQLSERVER_PASSWORD"\s*:\s*"([^"]*)"')
    if (-not $m.Success) {
        $c2Ok = $false
        $c2d = 'SQLSERVER_PASSWORD not in settings template'
    } else {
        $pw = $m.Groups[1].Value
        $placeholder = ($pw -match '(?i)^(CHANGE_ME|CHANGEME|REPLACE_ME|YOUR_PASSWORD|TODO|XXX|PLACEHOLDER)?$') -or ($pw -eq '')
        if (-not $placeholder -and $pw -match '(?i)change|replace|your_|todo|xxx|placeholder') {
            $placeholder = $true
        }
        if (-not $placeholder) {
            $c2Ok = $false
            $c2d = "real SQL password in template: $pw"
        } else {
            $c2d = "placeholder OK: $pw"
        }
    }
}
Add-Check 2 'add-user.sh SQL password placeholder only' $c2Ok $c2d

# --- CHECK 3: OAUTH not written to world-readable /etc/environment without chmod 600 ---
$c3Ok = $true
$c3hits = New-Object System.Collections.Generic.List[string]
foreach ($rel in @(
    'scripts/server/commands/install.sh',
    'scripts/server/commands/update-server.sh',
    'scripts/server/commands/deploy-auth.sh'
)) {
    $t = Read-Rel $rel
    if ($null -eq $t) { continue }
    $lines = $t -split "`r?`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $isTokenWrite = $false
        if ($line -match 'CLAUDE_CODE_OAUTH_TOKEN=\$NEW_TOKEN' -and $line -match '/etc/environment') {
            $isTokenWrite = $true
        }
        if ($line -match "echo 'CLAUDE_CODE_OAUTH_TOKEN=<token>' >> /etc/environment") {
            $isTokenWrite = $true
        }
        if ($line -match '>>\s*/etc/environment' -and $line -match 'CLAUDE_CODE_OAUTH_TOKEN') {
            $isTokenWrite = $true
        }
        if ($isTokenWrite) {
            $start = [Math]::Max(0, $i - 2)
            $end = [Math]::Min($lines.Count - 1, $i + 6)
            $window = ($lines[$start..$end]) -join "`n"
            if ($window -notmatch 'chmod\s+600\s+/etc/environment') {
                $c3Ok = $false
                $c3hits.Add(('{0}:{1}' -f $rel, ($i + 1)))
            }
        }
    }
}
$c3d = if ($c3Ok) { 'no unprotected /etc/environment OAUTH writes' } else { 'OAUTH write without chmod 600: ' + ($c3hits -join ', ') }
Add-Check 3 'OAUTH token not world-readable /etc/environment' $c3Ok $c3d

# --- CHECK 4: golden auth.json not installed 644 ---
$c4Ok = $true
$c4hits = New-Object System.Collections.Generic.List[string]
foreach ($rel in @(
    'scripts/server/cursor-auth-export.sh',
    'scripts/server/cursor-auth-sync.sh',
    'scripts/server/commands/install.sh',
    'scripts/server/commands/sync-cursor-auth.sh'
)) {
    $t = Read-Rel $rel
    if ($null -eq $t) { continue }
    if ($t -match 'chmod\s+644\s+/etc/cursor-auth/golden') {
        $c4Ok = $false
        $c4hits.Add("$rel chmod 644 golden")
    }
    if ($t -match 'install\s+-m\s+644[^\r\n]*auth\.json') {
        $c4Ok = $false
        $c4hits.Add("$rel install -m 644 auth.json")
    }
}
$c4d = if ($c4Ok) { 'no 644 install of golden auth.json' } else { ($c4hits | Select-Object -Unique) -join '; ' }
Add-Check 4 'golden auth.json not mode 644' $c4Ok $c4d

# --- CHECK 5: sudo password not echoed on cmdline in client scripts ---
$c5Ok = $true
$c5hits = New-Object System.Collections.Generic.List[string]
$clientDir = Join-Path $RepoRoot 'scripts/client'
if (Test-Path $clientDir) {
    $files = Get-ChildItem -Path $clientDir -Recurse -Include *.ps1,*.sh,*.bat -File -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($RepoRoot.Length).TrimStart('\', '/')
        $t = [IO.File]::ReadAllText($f.FullName)
        if ($t -match "echo\s+'[^']{4,}'\s*\|\s*sudo\s+-S") {
            $c5Ok = $false
            $c5hits.Add("$rel echo literal | sudo -S")
        }
        if ($t -match 'echo\s+"\$[A-Za-z0-9_]*PASS[A-Za-z0-9_]*"\s*\|\s*sudo') {
            $c5Ok = $false
            $c5hits.Add(($rel + ' echo $PASS | sudo'))
        }
        # askpass: printf 'echo '; printf '%q' "$LAPTOP_ADMIN_PW"  => password on echo cmdline when askpass runs
        if ($t -match "printf 'echo '" -and $t -match 'LAPTOP_ADMIN_PW' -and $t -notmatch 'askpass-secret') {
            $c5Ok = $false
            $c5hits.Add("$rel askpass embeds password in echo cmdline")
        }
    }
}
$c5d = if ($c5Ok) { 'no sudo password echoed on cmdline' } else { ($c5hits | Select-Object -Unique) -join '; ' }
Add-Check 5 'client scripts no sudo password on cmdline' $c5Ok $c5d

# --- CHECK 6: no unrestricted sepidz key merge / NOPASSWD for all keys ---
$bundle = Read-Rel 'scripts/server/commands/install-client-bundle.sh'
$sudoers = Read-Rel 'scripts/server/sudoers.d/claude-client-deploy'
$c6Ok = $true
$c6d = ''
if ($null -eq $bundle) {
    $c6Ok = $false
    $c6d = 'install-client-bundle.sh missing'
} else {
    $mergesAll = $false
    if ($bundle -match '_sync_sepidz_update_keys' -and $bundle -match 'for d in /home/\*' -and $bundle -match 'authorized_keys') {
        $mergesAll = $true
    }
    $sepidzNopass = $false
    if ($sudoers -and ($sudoers -match '(?m)^sepidz\s+ALL=\(root\)\s*NOPASSWD')) {
        $sepidzNopass = $true
    }
    if ($mergesAll) {
        $c6Ok = $false
        $c6d = 'unrestricted sepidz authorized_keys merge from ALL /home/* keys'
        if ($sepidzNopass) { $c6d += '; sepidz also has NOPASSWD' }
    } elseif ($sepidzNopass) {
        $c6Ok = $false
        $c6d = 'sepidz has NOPASSWD in claude-client-deploy'
    } else {
        $c6d = 'no unrestricted all-users key merge; sepidz lacks NOPASSWD'
    }
}
Add-Check 6 'no unrestricted sepidz key merge/NOPASSWD for all keys' $c6Ok $c6d

Write-Host ''
$overall = if ($failCount -eq 0) { 'HARD PASS' } else { 'HARD FAIL' }
$ocolor = if ($failCount -eq 0) { 'Green' } else { 'Red' }
Write-Host ("Overall: {0} ({1} FAIL / {2} checks)" -f $overall, $failCount, $results.Count) -ForegroundColor $ocolor
Write-Host ''

foreach ($r in $results) { Write-Output "RESULT|$r" }
Write-Output ("OVERALL|{0}|{1}" -f $overall, $failCount)

if ($failCount -gt 0) { exit 1 } else { exit 0 }
