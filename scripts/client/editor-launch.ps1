# editor-launch.ps1 - shared VS Code/Cursor launch (dot-sourced by connect.ps1)
# Same pattern as mac/connect.sh:  cursor|code --folder-uri "vscode-remote://..."

function Get-CursorRemoteProfileSite {
    # Smart vs Sepidz must NOT share one laptop Cursor profile / golden merge.
    # Prefer explicit script scope set by connect.ps1; fall back to ServerIP / Alias.
    if ($script:CursorProfileSite) {
        $s = [string]$script:CursorProfileSite
        if ($s -match '(?i)^sepidz') { return 'Sepidz' }
        if ($s -match '(?i)^smart') { return 'Smart' }
    }
    $ip = ''
    if ($script:ServerIP) { $ip = [string]$script:ServerIP }
    if ($ip -eq '192.168.250.70') { return 'Sepidz' }
    if ($ip -eq '192.168.210.240') { return 'Smart' }
    $al = ''
    if ($script:SshAlias) { $al = [string]$script:SshAlias }
    if ($al -match '(?i)sepidz') { return 'Sepidz' }
    return 'Smart'
}

function Get-CursorRemoteProfileDir {
    # Isolated Cursor profile for server Remote-SSH. Smart and Sepidz use
    # separate dirs so each site's golden Cursor account cannot overwrite
    # the other. Personal Cursor (%APPDATA%\Cursor) is never touched.
    $site = Get-CursorRemoteProfileSite
    if ($site -eq 'Sepidz') {
        return (Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile-Sepidz')
    }
    return (Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile-Smart')
}

function Get-CursorWindowTitleTag {
    # Single source of truth for the literal window-title tag text
    # Initialize-CursorServerProfile actually writes for a given site ("Claude Server Smart" /
    # "Claude Server Sepidz"). Shared by Initialize-CursorServerProfile (the writer) and
    # Get-CursorWindowTitleNeedle (the 4 readers, bug 2) so the two can never drift apart again.
    param(
        [string]$Site = (Get-CursorRemoteProfileSite)
    )
    if ($Site -eq 'Sepidz') { return 'Claude Server Sepidz' }
    return 'Claude Server Smart'
}

function Get-CursorWindowTitleNeedle {
    # Bug 2 fix: the 4 window-title match call sites (Test-CursorWindowTitleIsAgentHome,
    # Test-RemoteEditorOnCorrectFolder, Get-RemoteEditorSessionPresence,
    # Get-RemoteEditorStateExplain) used to hardcode the literal regex '\[Claude Server\]', but
    # Initialize-CursorServerProfile has ALWAYS written a site-qualified tag ("[Claude Server
    # Smart]" / "[Claude Server Sepidz]") - the bare, unqualified form is never actually rendered
    # by production code, so that literal regex was permanently dead against every real window.
    # Build the needle dynamically from the SAME Get-CursorWindowTitleTag/
    # Get-CursorRemoteProfileSite source of truth the writer uses, instead of a hand-maintained
    # alternation that could silently drift from it again. The bare '\[Claude Server\]'
    # alternative is kept only as a defensive fallback for a settings.json written to disk before
    # this fix shipped (Initialize-CursorServerProfile never rewrites an existing settings.json,
    # so a pre-existing profile could still carry the old bare-tag title until next profile reset).
    $tag = Get-CursorWindowTitleTag
    return '\[' + [regex]::Escape($tag) + '\]|\[Claude Server\]'
}

function Test-CursorWindowTitleMatchesProject {
    # A server-profile window title belongs to THIS project iff the project's root folder name
    # appears at the exact position the title templates place it, with a trailing non-path boundary:
    #   custom template : "${dirty}${editor}${sep}[Claude Server <Site>] <rootName>"  (root AFTER the tag)
    #   Cursor SSH title: "<...> <rootName> [SSH: <alias>] - Cursor"                   (root BEFORE [SSH:])
    #
    # Matching $rootName ANYWHERE in the title (the old '$title -match $rootNeedle') is wrong on two
    # counts, both hit live 2026-07-25:
    #   1) Site-tag collision: the tag itself is "[Claude Server Smart]", so a project literally named
    #      "smart" matched EVERY open server window - selecting project "smart" foregrounded an
    #      unrelated window and skipped the launch (reason=known_on_folder), so smart never opened.
    #   2) Prefix-sibling collision: a bare/word-boundary substring also matched "smart" inside
    #      "smartdesk" and "ai" inside "ai-gap-summay" (hyphen is a \b boundary), cross-detecting
    #      siblings. Anchor to the template position and require the boundary so "smart" != "smartdesk".
    param(
        [string]$Title,
        [Parameter(Mandatory)][string]$RootName,
        [string]$TitleTag = (Get-CursorWindowTitleTag),
        [string]$AliasNeedleEscaped = ''
    )
    if (-not $Title -or -not $RootName) { return $false }
    $rootEsc = [regex]::Escape($RootName)
    $boundary = '(?![\w./-])'
    if ($Title -match ('\[' + [regex]::Escape($TitleTag) + '\]\s+' + $rootEsc + $boundary)) { return $true }
    # Defensive: a settings.json written before the site-qualified tag shipped uses the bare tag.
    if ($Title -match ('\[Claude Server\]\s+' + $rootEsc + $boundary)) { return $true }
    # Cursor's own default Remote-SSH title places the folder name IMMEDIATELY before the [SSH: <alias>]
    # marker: "<rootName> [SSH: <alias>] - Cursor". The gap here must be whitespace only (\s*), NOT the
    # old greedy [^\[]* - live regression 2026-07-25: with the site-qualified custom title
    # "[Claude Server Smart] refactoreoldclub [SSH: claude-server]", a search for project "smart"
    # case-insensitively matched the "Smart" in the SITE TAG, then [^\[]* skipped across
    # "] refactoreoldclub " to "[SSH:", so on_folder returned TRUE for "smart" even though no smart
    # window was open -> connect skipped the launch and project "smart" never opened. \s* anchors the
    # root right before [SSH:, so the site-tag "Smart" (followed by "]") can no longer reach the marker.
    if ($AliasNeedleEscaped -and
        $Title -match ('(?<![\w./-])' + $rootEsc + $boundary + '\s*\[SSH:\s*' + $AliasNeedleEscaped + '\]')) { return $true }
    return $false
}

function Get-CursorServerWindowTitleTemplate {
    param([string]$TitleTag)
    # The VS Code ${...} tokens MUST reach settings.json literally. The old code built this inside a
    # double-quoted here-string, so PowerShell expanded ${dirty}/${activeEditorShort}/${separator}/
    # ${rootName} to EMPTY - settings.json ended up as "[Claude Server Smart] " with no folder name.
    # Remote windows then never showed the project name, and title-based on_folder / agent-home
    # detection could not tell one project window from another (live regression 2026-07-25: every
    # launch reported failure / "drifted to Agent/home" because the folder was invisible in the title).
    # Build it via string concatenation so the tokens stay literal regardless of quoting.
    return ('${dirty}${activeEditorShort}${separator}[' + $TitleTag + '] ${rootName}')
}

function Repair-CursorServerWindowTitle {
    param(
        [Parameter(Mandatory)][string]$SettingsPath,
        [Parameter(Mandatory)][string]$TitleTag
    )
    # In-place repair for profiles created before the here-string bug fix: if window.title is present
    # but lost its ${rootName} token, rewrite ONLY that value (string-level, so JSONC comments / other
    # user settings survive). No-op when the token is already there.
    try {
        if (-not (Test-Path $SettingsPath)) { return $false }
        $raw = Get-Content -LiteralPath $SettingsPath -Raw -Encoding UTF8
        if ($raw -notmatch '"window\.title"\s*:\s*"') { return $false }
        if ($raw -match '"window\.title"\s*:\s*"[^"]*\$\{rootName\}') { return $false }
        $correctVal = Get-CursorServerWindowTitleTemplate -TitleTag $TitleTag
        $replacement = '"window.title": "' + $correctVal + '"'
        $new = [regex]::Replace(
            $raw,
            '"window\.title"\s*:\s*"[^"]*"',
            [System.Text.RegularExpressions.MatchEvaluator] { param($m) $replacement },
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )
        if ($new -ne $raw) {
            Set-Content -LiteralPath $SettingsPath -Value $new -Encoding UTF8
            if (Get-Command Write-EditorLaunchLog -ErrorAction SilentlyContinue) {
                Write-EditorLaunchLog 'PROFILE_REPAIR: window.title restored ${rootName} token' 'INFO'
            }
            return $true
        }
    } catch { }
    return $false
}

function Initialize-CursorServerProfile {
    # First-run: make the server window visually distinct from personal Cursor. On later runs, repair
    # a window.title that lost its ${rootName} token (older here-string bug) so remote windows show the
    # project name and detection can identify them.
    $userDir = Join-Path (Get-CursorRemoteProfileDir) 'User'
    $settingsPath = Join-Path $userDir 'settings.json'
    $site = Get-CursorRemoteProfileSite
    $titleTag = Get-CursorWindowTitleTag -Site $site
    if (Test-Path $settingsPath) {
        Repair-CursorServerWindowTitle -SettingsPath $settingsPath -TitleTag $titleTag | Out-Null
        return
    }
    if (-not (Test-Path $userDir)) {
        New-Item -ItemType Directory -Force -Path $userDir | Out-Null
    }
    $barBg = if ($site -eq 'Sepidz') { '#3a1e5f' } else { '#1e3a5f' }
    $barBgIn = if ($site -eq 'Sepidz') { '#2a1545' } else { '#152a45' }
    $titleTemplate = Get-CursorServerWindowTitleTemplate -TitleTag $titleTag
    $json = @"
{
  "window.title": "$titleTemplate",
  "workbench.colorCustomizations": {
    "titleBar.activeBackground": "$barBg",
    "titleBar.activeForeground": "#e8e8e8",
    "titleBar.inactiveBackground": "$barBgIn",
    "titleBar.inactiveForeground": "#a0a0a0"
  }
}
"@
    $json | Set-Content -Path $settingsPath -Encoding UTF8
}



function Ensure-CursorRemoteSshQuietSettings {
    # Cursor Remote-SSH on Windows spawns visible cmd.exe pipes for
    # cursor_remote_install_*.sh (one per host). Hide the login terminal so
    # those consoles are not shown after Opening Cursor.
    $userDir = Join-Path (Get-CursorRemoteProfileDir) 'User'
    $settingsPath = Join-Path $userDir 'settings.json'
    if (-not (Test-Path $userDir)) { New-Item -ItemType Directory -Force -Path $userDir | Out-Null }
    $obj = $null
    if (Test-Path $settingsPath) {
        try { $obj = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json -ErrorAction Stop } catch { $obj = $null }
    }
    if (-not $obj) { $obj = [PSCustomObject]@{} }
    $changed = $false
    $prop = $obj.PSObject.Properties['remote.SSH.showLoginTerminal']
    if ($prop) {
        if ($prop.Value -ne $false) { $prop.Value = $false; $changed = $true }
    } else {
        $obj | Add-Member -NotePropertyName 'remote.SSH.showLoginTerminal' -NotePropertyValue $false -Force
        $changed = $true
    }
    if ($changed) {
        ($obj | ConvertTo-Json -Depth 20) | Set-Content -Path $settingsPath -Encoding UTF8
        Write-EditorLaunchLog 'CURSOR_SSH_UI: showLoginTerminal=false' 'INFO'
    }
    return $changed
}

function Set-CursorProxySettings {
    # Points Cursor's own network stack (not just extensions) at the local -L forward that
    # git-mode.ps1 opened on the reverse-tunnel ssh process (server xray), so Cursor's
    # chat/agent/MCP requests egress via the VLESS exit IP instead of each laptop's own network.
    # settings.json http.proxy must be http:// (Node/undici rejects socks5); Chromium CLI stays socks5.
    param(
        [int]$SocksPort = 0,
        [int]$HttpPort = 0
    )
    $userDir = Join-Path (Get-CursorRemoteProfileDir) 'User'
    $settingsPath = Join-Path $userDir 'settings.json'
    if (-not (Test-Path $userDir)) { New-Item -ItemType Directory -Force -Path $userDir | Out-Null }
    if ($HttpPort -gt 0) {
        $proxyUrl = "http://127.0.0.1:$HttpPort"
    } elseif ($SocksPort -gt 0) {
        # Never write socks5 into settings.json: Cursor Node/MCP undici rejects it
        # ("Invalid URL protocol"). Chromium still uses --proxy-server=socks5 via CLI args.
        Write-EditorLaunchLog ("CURSOR_PROXY_SET: skip_settings no_http_leg socks={0} (CLI socks only)" -f $SocksPort) 'WARN'
        return $false
    } else {
        return $false
    }
    $obj = $null
    if (Test-Path $settingsPath) {
        try { $obj = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json -ErrorAction Stop } catch { $obj = $null }
    }
    if (-not $obj) { $obj = [PSCustomObject]@{} }
    $changed = $false
    foreach ($pair in @(
        @{ Name = 'http.proxy'; Value = $proxyUrl }
        @{ Name = 'https.proxy'; Value = $proxyUrl }
        @{ Name = 'http.proxyStrictSSL'; Value = $false }
        @{ Name = 'http.proxySupport'; Value = 'override' }
        @{ Name = 'cursor.general.proxyMode'; Value = 'custom' }
        @{ Name = 'cursor.general.disableHttp2'; Value = $true }
    )) {
        $prop = $obj.PSObject.Properties[$pair.Name]
        if ($prop) {
            if ("$($prop.Value)" -ne "$($pair.Value)") { $prop.Value = $pair.Value; $changed = $true }
        } else {
            $obj | Add-Member -NotePropertyName $pair.Name -NotePropertyValue $pair.Value -Force
            $changed = $true
        }
    }
    if ($changed) {
        ($obj | ConvertTo-Json -Depth 20) | Set-Content -Path $settingsPath -Encoding UTF8
        Write-EditorLaunchLog "CURSOR_PROXY_SET: proxy=$proxyUrl changed=1" 'INFO'
    }
    return $changed
}

function Clear-CursorProxySettings {
    # Remove proxy keys when xray is down or server has no xray (Sepidz) - must match no-feature state.
    $userDir = Join-Path (Get-CursorRemoteProfileDir) 'User'
    $settingsPath = Join-Path $userDir 'settings.json'
    if (-not (Test-Path $settingsPath)) { return $false }
    $obj = $null
    try { $obj = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json -ErrorAction Stop } catch { return $false }
    if (-not $obj) { return $false }
    $changed = $false
    foreach ($key in @('http.proxy', 'https.proxy', 'http.proxyStrictSSL', 'http.proxySupport', 'cursor.general.proxyMode', 'cursor.general.disableHttp2')) {
        $prop = $obj.PSObject.Properties[$key]
        if ($prop) {
            $obj.PSObject.Properties.Remove($key)
            $changed = $true
        }
    }
    if ($changed) {
        ($obj | ConvertTo-Json -Depth 20) | Set-Content -Path $settingsPath -Encoding UTF8
        Write-EditorLaunchLog 'CURSOR_PROXY_CLEAR: removed proxy keys changed=1' 'INFO'
    }
    return $changed
}

function Get-RunningCursorProxyCliPort {
    foreach ($p in @(Get-CursorMainProfileProcesses)) {
        try {
            $cim = Get-CimInstance Win32_Process -Filter "ProcessId=$($p.ProcessId)" -ErrorAction Stop
            $cmd = [string]$cim.CommandLine
            if ($cmd -match '--proxy-server=socks5://127\.0\.0\.1:(\d+)') {
                return [int]$Matches[1]
            }
        } catch {}
    }
    return 0
}

function Align-CursorProxyWithRunningCli {
    param([int]$SocksPort = 0, [int]$HttpPort = 0)
    $cliPort = Get-RunningCursorProxyCliPort
    $frontSocks = 0
    if ($script:CursorSocksFrontPort) { $frontSocks = [int]$script:CursorSocksFrontPort }
    # Sticky front (18999) wins over a live CLI still pinned to backend 19080.
    # Old windows keep their --proxy-server until relaunch; do NOT drag settings/launch
    # args back down to the backend port (defeats sidecar across tunnel reseed).
    if ($frontSocks -gt 0 -and $cliPort -gt 0 -and $cliPort -ne $frontSocks) {
        $frontUp = $false
        if (Get-Command Test-LocalPortOpen -ErrorAction SilentlyContinue) {
            $frontUp = [bool](Test-LocalPortOpen -PortNum $frontSocks)
        } elseif (Get-Command Test-CursorProxySidecarListening -ErrorAction SilentlyContinue) {
            $frontUp = [bool](Test-CursorProxySidecarListening -Port $frontSocks)
        }
        if ($frontUp) {
            Write-EditorLaunchLog ("CURSOR_PROXY_ALIGN: prefer_sticky_front socks={0} cli_legacy={1} (relaunch picks up front)" -f $frontSocks, $cliPort) 'WARN'
            $http = $HttpPort
            if ($script:CursorHttpFrontPort) { $http = [int]$script:CursorHttpFrontPort }
            return @{ Aligned = $true; SocksPort = $frontSocks; HttpPort = $http; LegacyCli = $cliPort }
        }
    }
    if ($cliPort -le 0) { return @{ Aligned = $false; SocksPort = $SocksPort; HttpPort = $HttpPort } }
    if ($SocksPort -gt 0 -and $cliPort -ne $SocksPort) {
        Write-EditorLaunchLog ("CURSOR_PROXY_ALIGN: prefer_running_cli socks={0} session={1}" -f $cliPort, $SocksPort) 'INFO'
        return @{ Aligned = $true; SocksPort = $cliPort; HttpPort = $HttpPort }
    }
    if ($cliPort -gt 0) {
        Write-EditorLaunchLog ("CURSOR_PROXY_ALIGN: prefer_running_cli socks={0} session={1}" -f $cliPort, $SocksPort) 'DEBUG'
    }
    return @{ Aligned = $true; SocksPort = $cliPort; HttpPort = $HttpPort }
}

function Test-MayClearCursorProxySettings {
    param([switch]$AllowClear)
    if ($null -ne $script:CursorProxyOwner -and -not $script:CursorProxyOwner) {
        Write-EditorLaunchLog 'CURSOR_PROXY_CLEAR_SKIP: reason=non_owner' 'WARN'
        return $false
    }
    $n = 0
    try { $n = @(Get-CursorProfileProcesses).Count } catch { $n = 0 }
    if ($n -gt 0) {
        Write-EditorLaunchLog ("CURSOR_PROXY_CLEAR_SKIP: reason=windows_open socks_null=1 profile_count={0}" -f $n) 'WARN'
        return $false
    }
    if (-not $AllowClear) {
        Write-EditorLaunchLog 'CURSOR_PROXY_CLEAR_SKIP: reason=no_allow_clear' 'DEBUG'
        return $false
    }
    return $true
}

function Get-CodeRemoteProfileDir {
    # Isolated VS Code profile for server Remote-SSH (parity with Mac ClaudeServerCodeProfile).
    return (Join-Path $env:LOCALAPPDATA 'ClaudeServerCodeProfile')
}

function Initialize-CodeServerProfile {
    $userDir = Join-Path (Get-CodeRemoteProfileDir) 'User'
    $settingsPath = Join-Path $userDir 'settings.json'
    if (Test-Path $settingsPath) { return }
    if (-not (Test-Path $userDir)) {
        New-Item -ItemType Directory -Force -Path $userDir | Out-Null
    }
    @'
{
  "window.title": "${dirty}${activeEditorShort}${separator}[Claude Server Code] ${rootName}",
  "workbench.colorCustomizations": {
    "titleBar.activeBackground": "#1e3a5f",
    "titleBar.activeForeground": "#e8e8e8",
    "titleBar.inactiveBackground": "#152a45",
    "titleBar.inactiveForeground": "#a0a0a0"
  }
}
'@ | Set-Content -Path $settingsPath -Encoding UTF8
}

function Ensure-EditorOnPath {
    param([string]$EditorCmd)
    $leaf = if ($EditorCmd -eq 'cursor') { 'cursor.cmd' } else { 'code.cmd' }
    $exeLeaf = if ($EditorCmd -eq 'cursor') { 'Cursor.exe' } else { 'Code.exe' }
    $relBin = if ($EditorCmd -eq 'cursor') { 'resources\app\bin' } else { 'bin' }
    $folder = if ($EditorCmd -eq 'cursor') { 'cursor' } else { 'Microsoft VS Code' }

    function ConvertTo-EditorCliFromRoot {
        param([string]$Root)
        if (-not $Root -or -not (Test-Path -LiteralPath $Root)) { return $null }
        $binDir = [System.IO.Path]::Combine($Root, $relBin)
        $cli = [System.IO.Path]::Combine($binDir, $leaf)
        if (Test-Path -LiteralPath $cli) { return $cli }
        $exe = [System.IO.Path]::Combine($Root, $exeLeaf)
        if (Test-Path -LiteralPath $exe) { return $exe }
        return $null
    }

    function Add-EditorBinToPath {
        param([string]$CliPath)
        if (-not $CliPath) { return $null }
        $binDir = Split-Path -Parent $CliPath
        # If we resolved Cursor.exe at install root, prefer resources\app\bin when present
        if ($CliPath -match '\\Cursor\.exe$' -or $CliPath -match '\\Code\.exe$') {
            $maybeBin = [System.IO.Path]::Combine((Split-Path -Parent $CliPath), $relBin)
            $maybeCli = [System.IO.Path]::Combine($maybeBin, $leaf)
            if (Test-Path -LiteralPath $maybeCli) {
                $CliPath = $maybeCli
                $binDir = $maybeBin
            }
        }
        if ($binDir -and ($env:Path -notlike "*$([regex]::Escape($binDir))*")) {
            $env:Path = "$binDir;$env:Path"
        }
        return $CliPath
    }

    # 1) Preferred accounts first (LaptopUser / current), then every local profile.
    #    Fixes Admin connect when Cursor is installed under another Windows user.
    $userNames = New-Object System.Collections.Generic.List[string]
    foreach ($u in @($script:LaptopUser, $env:USERNAME)) {
        if ($u -and -not $userNames.Contains($u)) { [void]$userNames.Add($u) }
    }
    $usersRoot = 'C:\Users'
    if (Test-Path -LiteralPath $usersRoot) {
        Get-ChildItem -LiteralPath $usersRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notin @('Public', 'Default', 'Default User', 'All Users') } |
            ForEach-Object {
                if (-not $userNames.Contains($_.Name)) { [void]$userNames.Add($_.Name) }
            }
    }

    foreach ($u in $userNames) {
        $root = [System.IO.Path]::Combine("C:\Users\$u\AppData\Local\Programs", $folder)
        $hit = ConvertTo-EditorCliFromRoot -Root $root
        if ($hit) { return (Add-EditorBinToPath -CliPath $hit) }
    }

    # 2) Current LOCALAPPDATA + machine-wide Program Files
    $candidateRoots = @(
        $(if ($env:LOCALAPPDATA) { [System.IO.Path]::Combine($env:LOCALAPPDATA, 'Programs', $folder) } else { $null }),
        $(if ($env:ProgramFiles) { [System.IO.Path]::Combine($env:ProgramFiles, $folder) } else { $null }),
        $(if (${env:ProgramFiles(x86)}) { [System.IO.Path]::Combine(${env:ProgramFiles(x86)}, $folder) } else { $null })
    ) | Where-Object { $_ }
    foreach ($root in $candidateRoots) {
        $hit = ConvertTo-EditorCliFromRoot -Root $root
        if ($hit) { return (Add-EditorBinToPath -CliPath $hit) }
    }

    # 3) Already on PATH (Get-Command)
    $cmd = Get-Command $EditorCmd -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) {
        return (Add-EditorBinToPath -CliPath $cmd.Source)
    }

    return $null
}

function Show-EditorAutoPick {
    param(
        [Parameter(Mandatory)][string]$PickedName,
        [Parameter(Mandatory)][string]$OtherName,
        [Parameter(Mandatory)][string]$OtherReason
    )
    Write-Host ''
    Write-Host '    Open with' -ForegroundColor White
    Write-Host ''
    Write-Host "    $PickedName  <- only option, opening automatically" -ForegroundColor DarkGray
    Write-Host "    $OtherName  (unavailable - $OtherReason)" -ForegroundColor DarkGray
    Write-Host ''
}

function Get-EditorPref {
    param([Parameter(Mandatory)][string]$CfgDir)
    $EditorPrefFile = [System.IO.Path]::Combine($CfgDir, 'editor.conf')
    if (-not (Test-Path $EditorPrefFile)) { return 'cursor' }
    $saved = (Get-Content $EditorPrefFile -Raw -ErrorAction SilentlyContinue).Trim().ToLower()
    if ($saved -eq 'vscode') { $saved = 'code' }
    if ($saved -match '^(rider|both)$') { Remove-Item $EditorPrefFile -ErrorAction SilentlyContinue; return 'cursor' }
    if ($saved -in @('cursor', 'code', 'ask')) { return $saved }
    return 'cursor'
}

function Show-EditorPickMenu {
    param(
        [Parameter(Mandatory)][string]$CfgDir,
        [string]$Saved = 'cursor',
        [switch]$PersistChoice
    )
    Write-Host ''
    Write-Host '    Open with' -ForegroundColor White
    Write-Host ''
    Write-Host '    1  Cursor' -ForegroundColor DarkGray
    Write-Host '    2  VS Code' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host "    (Enter = $Saved)" -ForegroundColor DarkGray
    $edChoice = (Read-Host '    >').Trim().ToLower()
    $EditorCmd = 'cursor'
    $EditorName = 'Cursor'
    switch ($edChoice) {
        { $_ -in '1', 'cursor', 'c' } { $EditorCmd = 'cursor'; $EditorName = 'Cursor' }
        { $_ -in '2', 'code', 'vscode', 'v' } { $EditorCmd = 'code'; $EditorName = 'VS Code' }
        '' {
            if ($Saved -eq 'code') { $EditorCmd = 'code'; $EditorName = 'VS Code' }
        }
        default { $EditorCmd = 'cursor'; $EditorName = 'Cursor' }
    }
    if ($PersistChoice) {
        $EditorPrefFile = [System.IO.Path]::Combine($CfgDir, 'editor.conf')
        Set-Content -Path $EditorPrefFile -Value $EditorCmd -Encoding ASCII | Out-Null
    }
    return ,([PSCustomObject]@{ EditorCmd = $EditorCmd; EditorName = $EditorName })
}

function Configure-EditorPref {
    param([Parameter(Mandatory)][string]$CfgDir)
    Write-Host ''
    Write-Host '    IDE preference' -ForegroundColor White
    Write-Host ''
    $cur = Get-EditorPref -CfgDir $CfgDir
    Write-Host "    Current: $cur" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '    1  cursor - always open Cursor' -ForegroundColor DarkGray
    Write-Host '    2  code   - always open VS Code' -ForegroundColor DarkGray
    Write-Host '    3  ask    - pick each connect' -ForegroundColor DarkGray
    Write-Host ''
    $choice = (Read-Host '    >').Trim().ToLower()
    $val = switch ($choice) {
        { $_ -in '1', 'cursor', 'c' } { 'cursor' }
        { $_ -in '2', 'code', 'vscode', 'v' } { 'code' }
        { $_ -in '3', 'ask', 'a' } { 'ask' }
        default { $null }
    }
    if (-not $val) { Warn 'Invalid choice.'; return }
    Set-Content -Path ([System.IO.Path]::Combine($CfgDir, 'editor.conf')) -Value $val -Encoding ASCII | Out-Null
    Write-Host "    Saved: $val" -ForegroundColor Green
    Write-Host ''
}

function Resolve-EditorChoice {
    param(
        [Parameter(Mandatory)][string]$CfgDir
    )

    # Path.Combine - Join-Path binds pipeline input and causes ChildPath prompt
    $EditorPrefFile = [System.IO.Path]::Combine($CfgDir, 'editor.conf')
    Ensure-EditorOnPath 'cursor' | Out-Null
    Ensure-EditorOnPath 'code' | Out-Null
    $haveCursor = [bool](Get-Command cursor -ErrorAction SilentlyContinue)
    $haveCode   = [bool](Get-Command code   -ErrorAction SilentlyContinue)

    if (-not $haveCursor -and -not $haveCode) {
        return $null
    }

    if ($haveCursor -and -not $haveCode) {
        Show-EditorAutoPick -PickedName 'Cursor' -OtherName 'VS Code' -OtherReason 'not installed, or missing the Remote-SSH extension'
        return ,([PSCustomObject]@{ EditorCmd = 'cursor'; EditorName = 'Cursor' })
    }
    if (-not $haveCursor -and $haveCode) {
        Show-EditorAutoPick -PickedName 'VS Code' -OtherName 'Cursor' -OtherReason 'not installed, or install is broken'
        return ,([PSCustomObject]@{ EditorCmd = 'code'; EditorName = 'VS Code' })
    }

    $pref = Get-EditorPref -CfgDir $CfgDir
    if ($pref -eq 'ask') {
        return ,@(Show-EditorPickMenu -CfgDir $CfgDir -Saved 'cursor' -PersistChoice)[-1]
    }
    if ($pref -eq 'code') {
        return ,([PSCustomObject]@{ EditorCmd = 'code'; EditorName = 'VS Code' })
    }
    return ,([PSCustomObject]@{ EditorCmd = 'cursor'; EditorName = 'Cursor' })
}

function Test-IsElevatedShell {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-InteractiveWindowsUser {
    try {
        $owner = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
        if ($owner) {
            $name = ($owner -split '\\')[-1]
            if ($name) { return $name }
        }
    } catch {}
    return $env:USERNAME
}

function Get-InteractiveWindowsUserQualified {
    # schtasks /RU needs DOMAIN\user (short "User" is ambiguous / often fails /IT).
    try {
        $owner = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
        if ($owner -and ($owner -match '\\')) { return $owner }
        if ($owner) { return "$env:COMPUTERNAME\$owner" }
    } catch {}
    $u = Get-InteractiveWindowsUser
    if ($u -match '\\') { return $u }
    return "$env:COMPUTERNAME\$u"
}

function Get-EditorNativeExe {
    param([Parameter(Mandatory)][string]$EditorCmd)
    $cli = Ensure-EditorOnPath $EditorCmd
    if (-not $cli) { return $null }
    if ($EditorCmd -ne 'cursor') { return $cli }
    if ($cli -match '\\Cursor\.exe$') { return $cli }
    $binDir = Split-Path $cli -Parent
    $root = Split-Path (Split-Path (Split-Path $binDir -Parent) -Parent) -Parent
    $exe = Join-Path $root 'Cursor.exe'
    if (Test-Path $exe) { return $exe }
    return $cli
}

function Show-ConnectConsoleIfHidden {
    try {
        if (-not ('Win32.ConnectConsole' -as [type])) {
            Add-Type -Name ConnectConsole -Namespace Win32 -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
'@ -ErrorAction Stop
        }
        [Win32.ConnectConsole]::ShowWindow([Win32.ConnectConsole]::GetConsoleWindow(), 5) | Out-Null
    } catch {}
}

function Stop-CursorServerProfileTree {
    param([string]$ProfileDir = (Get-CursorRemoteProfileDir))
    $procs = @(Get-CursorProfileProcesses -ProfileDir $ProfileDir)
    if ($procs.Count -eq 0) { return }
    $seen = @{}
    foreach ($p in $procs) {
        if ($seen[$p.ProcessId]) { continue }
        $seen[$p.ProcessId] = $true
        $cmd = Format-EditorProcessCommandLine -CommandLine $p.CommandLine -MaxLen 120
        Write-EditorLaunchLog "LAUNCH_KILL_PROC: pid=$($p.ProcessId) cmd=$cmd" 'DEBUG'
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 200
}

function Initialize-NonElevatedLauncher {
    if ($script:NonElevatedLauncherReady) { return }
    if (-not ('NonElevatedLauncher' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

public static class NonElevatedLauncher
{
    // PROCESS_QUERY_LIMITED_INFORMATION works on Win10/11 when full QUERY is denied.
    const int PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
    const int PROCESS_QUERY_INFORMATION = 0x0400;
    const uint TOKEN_DUPLICATE = 0x0002;
    const uint TOKEN_QUERY = 0x0008;
    const uint TOKEN_ASSIGN_PRIMARY = 0x0001;
    const int SecurityImpersonation = 2;
    const int TokenPrimary = 1;
    const uint CREATE_UNICODE_ENVIRONMENT = 0x00000400;
    // Hard-detach from parent console so Cursor Electron/Node stderr cannot flood connect.bat.
    const uint DETACHED_PROCESS = 0x00000008;
    const uint CREATE_NEW_PROCESS_GROUP = 0x00000200;
    const int SW_SHOW = 5;
    public static int LastWin32Error;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct STARTUPINFO {
        public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
        public int dwX; public int dwY; public int dwXSize; public int dwYSize;
        public int dwXCountChars; public int dwYCountChars; public int dwFillAttribute;
        public int dwFlags; public short wShowWindow; public short cbReserved2;
        public IntPtr lpReserved2; public IntPtr hStdInput; public IntPtr hStdOutput; public IntPtr hStdError;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct PROCESS_INFORMATION {
        public IntPtr hProcess; public IntPtr hThread; public int dwProcessId; public int dwThreadId;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr OpenProcess(int access, bool inherit, int pid);
    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool OpenProcessToken(IntPtr h, uint access, out IntPtr tok);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr h);
    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool DuplicateTokenEx(IntPtr hExisting, uint dwDesiredAccess, IntPtr lpTokenAttributes, int ImpersonationLevel, int TokenType, out IntPtr phNewToken);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateProcessWithTokenW(IntPtr hToken, uint dwLogonFlags, string lpApplicationName, StringBuilder lpCommandLine, uint dwCreationFlags, IntPtr lpEnvironment, string lpCurrentDirectory, ref STARTUPINFO lpStartupInfo, out PROCESS_INFORMATION lpProcessInformation);

    static Process FindExplorer() {
        int sid = Process.GetCurrentProcess().SessionId;
        foreach (Process p in Process.GetProcessesByName("explorer")) {
            if (p.SessionId == sid) { return p; }
        }
        return null;
    }

    public static bool Start(string file, string args) {
        LastWin32Error = 0;
        Process explorer = FindExplorer();
        if (explorer == null) { LastWin32Error = 2; return false; }
        IntPtr hProc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, explorer.Id);
        if (hProc == IntPtr.Zero) {
            hProc = OpenProcess(PROCESS_QUERY_INFORMATION, false, explorer.Id);
        }
        if (hProc == IntPtr.Zero) { LastWin32Error = Marshal.GetLastWin32Error(); return false; }
        IntPtr hTok;
        if (!OpenProcessToken(hProc, TOKEN_DUPLICATE | TOKEN_QUERY, out hTok)) {
            LastWin32Error = Marshal.GetLastWin32Error();
            CloseHandle(hProc);
            return false;
        }
        IntPtr hDup;
        if (!DuplicateTokenEx(hTok, TOKEN_ASSIGN_PRIMARY | TOKEN_DUPLICATE | TOKEN_QUERY, IntPtr.Zero, SecurityImpersonation, TokenPrimary, out hDup)) {
            LastWin32Error = Marshal.GetLastWin32Error();
            CloseHandle(hTok);
            CloseHandle(hProc);
            return false;
        }
        CloseHandle(hTok);
        CloseHandle(hProc);
        STARTUPINFO si = new STARTUPINFO();
        si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
        si.lpDesktop = "winsta0\\default";
        si.dwFlags = 1;
        si.wShowWindow = SW_SHOW;
        PROCESS_INFORMATION pi;
        StringBuilder cmd = new StringBuilder(32768);
        cmd.Append('"');
        cmd.Append(file);
        cmd.Append('"');
        if (!string.IsNullOrEmpty(args)) {
            cmd.Append(' ');
            cmd.Append(args);
        }
        // LOGON_WITH_PROFILE (1): load user hive. Do NOT set CREATE_UNICODE_ENVIRONMENT with
        // null env (that can inherit the elevated block and break GUI apps).
        // DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP: isolate from elevated parent console;
        // SW_SHOW still shows the GUI window.
        const uint LOGON_WITH_PROFILE = 0x00000001;
        uint creationFlags = DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP;
        bool ok = CreateProcessWithTokenW(hDup, LOGON_WITH_PROFILE, null, cmd, creationFlags, IntPtr.Zero, null, ref si, out pi);
        if (!ok) { LastWin32Error = Marshal.GetLastWin32Error(); }
        CloseHandle(hDup);
        if (ok) {
            CloseHandle(pi.hProcess);
            CloseHandle(pi.hThread);
        }
        return ok;
    }
}
'@ -ErrorAction Stop
    }
    $script:NonElevatedLauncherReady = $true
}

function Invoke-SchTasksQuiet {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$ArgumentList)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'schtasks.exe'
    $psi.Arguments = (($ArgumentList | ForEach-Object {
        if ($null -eq $_) { return '' }
        $s = [string]$_
        if ($s -match '\s') { '"' + ($s -replace '"', '\"') + '"' } else { $s }
    }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    [void]$p.StandardOutput.ReadToEnd()
    [void]$p.StandardError.ReadToEnd()
    $p.WaitForExit()
    return $p.ExitCode
}

function Initialize-EditorLaunchTask {
    if ($script:EditorLaunchTaskReady) { return $true }
    $taskName = 'ClaudeServerEditorLaunch'
    $dir = Join-Path $env:LOCALAPPDATA 'ClaudeConnect'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $helper = Join-Path $dir 'launch-editor.ps1'
    @'
$ErrorActionPreference = "Stop"
$log = Join-Path $env:LOCALAPPDATA "ClaudeConnect\launch-editor.log"
function Write-LaunchHelperLog([string]$m) {
  try {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    Add-Content -LiteralPath $log -Value "[$ts] $m" -Encoding UTF8
  } catch {}
}
try {
  $specPath = Join-Path $env:LOCALAPPDATA "ClaudeConnect\launch-spec.json"
  $spec = Get-Content $specPath -Raw | ConvertFrom-Json
  $args = @()
  if ($spec.Args) { $args = @([string[]]$spec.Args) }
  Write-LaunchHelperLog ("start exe=" + $spec.FilePath + " argc=" + $args.Count)
  $p = Start-Process -FilePath $spec.FilePath -ArgumentList $args -WindowStyle Normal -PassThru
  Write-LaunchHelperLog ("started pid=" + $p.Id)
} catch {
  Write-LaunchHelperLog ("FAIL " + $_.Exception.Message)
  exit 1
}
exit 0
'@ | Set-Content -Path $helper -Encoding UTF8
    $user = Get-InteractiveWindowsUserQualified
    Write-EditorLaunchLog "LAUNCH_TASK: recreate RU=$user" 'DEBUG'
    $tr = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$helper`""
    if ((Invoke-SchTasksQuiet /Query /TN $taskName) -eq 0) {
        [void](Invoke-SchTasksQuiet /Delete /F /TN $taskName)
    }
    $createExit = Invoke-SchTasksQuiet /Create /F /TN $taskName /TR $tr /SC ONCE /ST 00:00 /RU $user /RL LIMITED /IT
    if ($createExit -ne 0) {
        # Fallback: short name (older hosts)
        $short = Get-InteractiveWindowsUser
        Write-EditorLaunchLog "LAUNCH_TASK: qualified RU failed exit=$createExit; retry RU=$short" 'WARN'
        $createExit = Invoke-SchTasksQuiet /Create /F /TN $taskName /TR $tr /SC ONCE /ST 00:00 /RU $short /RL LIMITED /IT
    }
    $script:EditorLaunchTaskReady = ($createExit -eq 0)
    if (-not $script:EditorLaunchTaskReady) {
        Write-EditorLaunchLog "LAUNCH_TASK: create failed exit=$createExit" 'WARN'
    }
    return $script:EditorLaunchTaskReady
}

function Start-ProcessViaLaunchTask {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @()
    )
    if (-not (Initialize-EditorLaunchTask)) { return $false }
    $specPath = Join-Path $env:LOCALAPPDATA 'ClaudeConnect\launch-spec.json'
    @{ FilePath = $FilePath; Args = $ArgumentList } | ConvertTo-Json -Compress | Set-Content -Path $specPath -Encoding UTF8
    return ((Invoke-SchTasksQuiet /Run /TN 'ClaudeServerEditorLaunch') -eq 0)
}

function Format-ProcessArgumentString {
    param([string[]]$ArgumentList)
    return (($ArgumentList | ForEach-Object {
        if ($null -eq $_) { return '' }
        $s = [string]$_
        if ($s -match '\s') { '"' + ($s -replace '"', '\"') + '"' } else { $s }
    }) -join ' ')
}


function Get-EditorExeNameFromPath {
    param([Parameter(Mandatory)][string]$FilePath)
    $leaf = Split-Path $FilePath -Leaf
    if ($leaf -match '(?i)^cursor(\.exe|\.cmd)?$') { return 'Cursor.exe' }
    if ($leaf -match '(?i)^code(\.exe|\.cmd)?$') { return 'Code.exe' }
    if ($leaf -match '\.exe$') { return $leaf }
    return $null
}

function Get-EditorProfileDirFromArgs {
    param([string[]]$ArgumentList = @())
    for ($i = 0; $i -lt ($ArgumentList.Count - 1); $i++) {
        if ($ArgumentList[$i] -eq '--user-data-dir') { return $ArgumentList[$i + 1] }
    }
    return $null
}

function Test-EditorProcessEvidence {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [int]$TimeoutMs = 2000
    )
    $exeName = Get-EditorExeNameFromPath -FilePath $FilePath
    if (-not $exeName) { return $false }
    $profileDir = Get-EditorProfileDirFromArgs -ArgumentList $ArgumentList
    $profileNeedle = if ($profileDir) { [regex]::Escape($profileDir) } else { $null }
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    while ((Get-Date) -lt $deadline) {
        if (Get-Command Clear-CursorProcessCache -ErrorAction SilentlyContinue) { Clear-CursorProcessCache }
        $procs = @(Invoke-CimEditorProcessQuery -ExeName $exeName -Reason 'proc_start_verify' -ForceRefresh)
        if ($profileNeedle) {
            $procs = @($procs | Where-Object { $_.CommandLine -and ($_.CommandLine -match $profileNeedle) })
        }
        if ($procs.Count -gt 0) { return $true }
        Start-Sleep -Milliseconds 250
    }
    return $false
}

function Get-EditorProfileProcessesForLaunch {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [switch]$ForceRefresh
    )
    $exeName = if ($EditorCmd -eq 'cursor') { 'Cursor.exe' } else { 'Code.exe' }
    $profileDir = if ($EditorCmd -eq 'cursor') { Get-CursorRemoteProfileDir } else { Get-CodeRemoteProfileDir }
    if (-not $profileDir) { return @() }
    $needle = [regex]::Escape($profileDir)
    return @(Invoke-CimEditorProcessQuery -ExeName $exeName -Reason 'launch_profile_verify' -ForceRefresh:$ForceRefresh |
        Where-Object { $_.CommandLine -and ($_.CommandLine -match $needle) })
}

function Confirm-RemoteEditorLaunchVisible {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath,
        [int]$WaitMs = 500
    )
    # Check immediately first - the caller only reaches this function after Launch-RemoteEditor
    # already positively confirmed on_folder via its own poll loop moments earlier, so the
    # common case is already-true and the flat WaitMs sleep below was pure dead time on top of
    # that. Only sleep-and-retry (preserving the original WaitMs budget as a safety net for the
    # genuine elevated-launch window-visibility race) when the immediate check comes up empty.
    if (Get-Command Clear-CursorProcessCache -ErrorAction SilentlyContinue) { Clear-CursorProcessCache }
    if (Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath) { return $true }
    if (Test-RemoteEditorWindowOpen -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath) { return $true }
    if ($WaitMs -gt 0) {
        Start-Sleep -Milliseconds $WaitMs
        if (Get-Command Clear-CursorProcessCache -ErrorAction SilentlyContinue) { Clear-CursorProcessCache }
        if (Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath) { return $true }
        if (Test-RemoteEditorWindowOpen -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath) { return $true }
    }
    $profileProcs = @(Get-EditorProfileProcessesForLaunch -EditorCmd $EditorCmd -ForceRefresh)
    if ($profileProcs.Count -eq 0) { return $false }
    $mainProcs = if ($EditorCmd -eq 'cursor') {
        @(Get-CursorMainProfileProcesses)
    } else {
        @($profileProcs | Where-Object { $_.CommandLine -and ($_.CommandLine -notmatch '--type=') })
    }
    if ($mainProcs.Count -eq 0) { return $false }
    foreach ($p in $mainProcs) {
        try {
            $wp = [System.Diagnostics.Process]::GetProcessById($p.ProcessId)
            if ($wp.MainWindowHandle -ne [IntPtr]::Zero) { return $true }
        } catch {}
    }
    return $false
}

function Get-CursorLaunchDayLogPath {
    $logDir = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    return (Join-Path $logDir ("cursor-launch-{0}.log" -f (Get-Date -Format 'yyyyMMdd')))
}

function Initialize-EditorDetachedLaunch {
    if ($script:EditorDetachedLaunchReady) { return }
    if (-not ('EditorDetachedLaunch' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class EditorDetachedLaunch
{
    public const uint DETACHED_PROCESS = 0x00000008;
    public const uint CREATE_NEW_PROCESS_GROUP = 0x00000200;
    public const uint CREATE_NO_WINDOW = 0x08000000;
    const int STARTF_USESHOWWINDOW = 0x00000001;
    const int STARTF_USESTDHANDLES = 0x00000100;
    const short SW_SHOW = 5;
    const uint GENERIC_WRITE = 0x40000000;
    const uint FILE_SHARE_READ = 0x00000001;
    const uint FILE_SHARE_WRITE = 0x00000002;
    const uint CREATE_ALWAYS = 2;
    const uint FILE_ATTRIBUTE_NORMAL = 0x80;

    public static int LastWin32Error;

    [StructLayout(LayoutKind.Sequential)]
    struct SECURITY_ATTRIBUTES {
        public int nLength;
        public IntPtr lpSecurityDescriptor;
        public bool bInheritHandle;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct STARTUPINFO {
        public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
        public int dwX; public int dwY; public int dwXSize; public int dwYSize;
        public int dwXCountChars; public int dwYCountChars; public int dwFillAttribute;
        public int dwFlags; public short wShowWindow; public short cbReserved2;
        public IntPtr lpReserved2; public IntPtr hStdInput; public IntPtr hStdOutput; public IntPtr hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct PROCESS_INFORMATION {
        public IntPtr hProcess; public IntPtr hThread; public int dwProcessId; public int dwThreadId;
    }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateProcessW(string lpApplicationName, StringBuilder lpCommandLine,
        IntPtr lpProcessAttributes, IntPtr lpThreadAttributes, bool bInheritHandles,
        uint dwCreationFlags, IntPtr lpEnvironment, string lpCurrentDirectory,
        ref STARTUPINFO lpStartupInfo, out PROCESS_INFORMATION lpProcessInformation);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr h);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr CreateFileW(string lpFileName, uint dwDesiredAccess, uint dwShareMode,
        ref SECURITY_ATTRIBUTES lpSecurityAttributes, uint dwCreationDisposition,
        uint dwFlagsAndAttributes, IntPtr hTemplateFile);

    static IntPtr OpenInheritWrite(string path) {
        SECURITY_ATTRIBUTES sa = new SECURITY_ATTRIBUTES();
        sa.nLength = Marshal.SizeOf(typeof(SECURITY_ATTRIBUTES));
        sa.bInheritHandle = true;
        IntPtr h = CreateFileW(path, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE,
            ref sa, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, IntPtr.Zero);
        if (h == new IntPtr(-1)) { LastWin32Error = Marshal.GetLastWin32Error(); }
        return h;
    }

    // Direct Cursor/VS Code launch: CreateProcessW (no cmd.exe), argv intact, stdio to day logs,
    // DETACHED_PROCESS so connect console is never flooded. GUI still shows (SW_SHOW).
    public static int Start(string file, string args, string stdoutPath, string stderrPath, uint creationFlags) {
        LastWin32Error = 0;
        IntPtr hOut = OpenInheritWrite(stdoutPath);
        if (hOut == new IntPtr(-1)) { return 0; }
        IntPtr hErr = OpenInheritWrite(stderrPath);
        if (hErr == new IntPtr(-1)) {
            CloseHandle(hOut);
            return 0;
        }
        STARTUPINFO si = new STARTUPINFO();
        si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
        si.dwFlags = STARTF_USESHOWWINDOW | STARTF_USESTDHANDLES;
        si.wShowWindow = SW_SHOW;
        si.hStdInput = IntPtr.Zero;
        si.hStdOutput = hOut;
        si.hStdError = hErr;
        StringBuilder cmd = new StringBuilder(32768);
        cmd.Append('"');
        cmd.Append(file);
        cmd.Append('"');
        if (!string.IsNullOrEmpty(args)) {
            cmd.Append(' ');
            cmd.Append(args);
        }
        PROCESS_INFORMATION pi;
        bool ok = CreateProcessW(file, cmd, IntPtr.Zero, IntPtr.Zero, true, creationFlags,
            IntPtr.Zero, null, ref si, out pi);
        if (!ok) { LastWin32Error = Marshal.GetLastWin32Error(); }
        CloseHandle(hOut);
        CloseHandle(hErr);
        if (!ok) { return 0; }
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);
        return pi.dwProcessId;
    }
}
'@ -ErrorAction Stop
    }
    $script:EditorDetachedLaunchReady = $true
}

function Start-EditorProcessDirect {
    # Canonical Cursor/VS Code launch: CreateProcessW with ArgumentList argv (no cmd.exe wrap).
    # Warm --remote IPC handoff requires a direct Cursor.exe process - NOT cmd /C Quiet wrap.
    #
    # Stdio: Cursor's Node/Electron dumps DeprecationWarning / "disable-http2 is not in the list
    # of known options" / "Error mutex already exists" to the *parent console* when the child
    # inherits it. RedirectStandardOutput / RedirectStandardError to cursor-launch day logs, set
    # ELECTRON_NO_ATTACH_CONSOLE, AND hard-detach (DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP)
    # so connect stays clean without the Quiet wrap that broke IPC.
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @()
    )
    $logPath = Get-CursorLaunchDayLogPath
    $stdoutPath = $logPath -replace '\.log$', '.stdout.log'
    $stderrPath = $logPath -replace '\.log$', '.stderr.log'
    try {
        $stamp = '---- {0} pid-parent={1} ----' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $PID
        Add-Content -LiteralPath $logPath -Value $stamp -Encoding UTF8
    } catch { }

    $prevNoAttach = $env:ELECTRON_NO_ATTACH_CONSOLE
    $prevNoWarn = $env:NODE_NO_WARNINGS
    $env:ELECTRON_NO_ATTACH_CONSOLE = '1'
    $env:NODE_NO_WARNINGS = '1'
    try {
        Initialize-EditorDetachedLaunch
        $argStr = Format-ProcessArgumentString -ArgumentList $ArgumentList
        # RedirectStandardOutput / RedirectStandardError targets (day logs); Start-Process cannot
        # set DETACHED_PROCESS, so CreateProcessW opens those files with STARTF_USESTDHANDLES.
        $RedirectStandardOutput = $stdoutPath
        $RedirectStandardError = $stderrPath
        $creationFlags = [uint32]([EditorDetachedLaunch]::DETACHED_PROCESS -bor `
            [EditorDetachedLaunch]::CREATE_NEW_PROCESS_GROUP -bor `
            [EditorDetachedLaunch]::CREATE_NO_WINDOW)
        $procId = [EditorDetachedLaunch]::Start(
            $FilePath, $argStr, $RedirectStandardOutput, $RedirectStandardError, $creationFlags)
        if ($procId -le 0) {
            throw ("EditorDetachedLaunch CreateProcessW failed win32={0}" -f [EditorDetachedLaunch]::LastWin32Error)
        }
        return [System.Diagnostics.Process]::GetProcessById($procId)
    } finally {
        if ($null -eq $prevNoAttach) { Remove-Item Env:\ELECTRON_NO_ATTACH_CONSOLE -ErrorAction SilentlyContinue }
        else { $env:ELECTRON_NO_ATTACH_CONSOLE = $prevNoAttach }
        if ($null -eq $prevNoWarn) { Remove-Item Env:\NODE_NO_WARNINGS -ErrorAction SilentlyContinue }
        else { $env:NODE_NO_WARNINGS = $prevNoWarn }
    }
}

function Start-ProcessAsInteractiveUser {    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @()
    )
    $argPreview = Format-ProcessArgumentString -ArgumentList $ArgumentList
    if (-not (Test-IsElevatedShell)) {
        Write-EditorLaunchLog "PROC_START: mode=non_elevated_direct exe=$FilePath args=$argPreview" 'DEBUG'
        try {
            $p = Start-EditorProcessDirect -FilePath $FilePath -ArgumentList $ArgumentList
            if (-not $p) {
                Write-EditorLaunchLog 'PROC_START_FAIL: mode=non_elevated_direct Start-Process returned null' 'ERROR'
                return $false
            }
            Write-EditorLaunchLog ("PROC_START_OK: mode=non_elevated_direct pid={0}" -f $p.Id) 'DEBUG'
            return $true
        } catch {
            Write-EditorLaunchLog ("PROC_START_FAIL: mode=non_elevated_direct ex={0}" -f $_.Exception.Message) 'ERROR'
            return $false
        }
    }
    Write-EditorLaunchLog "PROC_START: mode=elevated exe=$FilePath args=$argPreview" 'DEBUG'
    # Refresh the scheduled task once per connect run (so RU/helper fixes apply after an
    # update) - NOT on every launch attempt. Launch-RemoteEditor tries up to 4 strategies
    # per call, and this path can be re-entered many times per session (retries, auth
    # relaunch, O to reopen). Resetting EditorLaunchTaskReady unconditionally forced a
    # /Delete + /Create of ClaudeServerEditorLaunch on every single attempt; deleting the
    # task definition while a just-triggered instance could still be mid-run detached that
    # instance from Task Scheduler's lifecycle tracking, leaking a powershell.exe host
    # process per attempt (confirmed: dozens of stale launch-editor.ps1 processes still
    # alive hours later in the same session).
    if (-not $script:EditorLaunchTaskRefreshedThisRun) {
        $script:EditorLaunchTaskReady = $false
        $script:EditorLaunchTaskRefreshedThisRun = $true
    }
    Initialize-NonElevatedLauncher
    $argStr = Format-ProcessArgumentString -ArgumentList $ArgumentList
    # Keep interactive attempts short: Aria/Mehrdad spent ~17s on Opening Cursor when
    # NonElevated+Task both failed before elevated_direct_fallback (which works).
    $evidenceMsNe = 2500
    $evidenceMsTask = 4000
    $evidenceMsDirect = 8000
    $neStarted = $false
    try {
        if ([NonElevatedLauncher]::Start($FilePath, $argStr)) {
            $neStarted = $true
            if (Test-EditorProcessEvidence -FilePath $FilePath -ArgumentList $ArgumentList -TimeoutMs $evidenceMsNe) {
                Write-EditorLaunchLog 'PROC_START_OK: mode=elevated_non_elevated_launcher' 'DEBUG'
                return $true
            }
            Write-EditorLaunchLog 'PROC_START_FAIL: mode=elevated_non_elevated_launcher no_process' 'DEBUG'
        } else {
            $winErr = 0
            try { $winErr = [NonElevatedLauncher]::LastWin32Error } catch {}
            Write-EditorLaunchLog "PROC_START_FAIL: mode=elevated_non_elevated_launcher Start=false win32=$winErr" 'DEBUG'
        }
    } catch {
        Write-EditorLaunchLog "PROC_START_WARN: NonElevatedLauncher exception=$($_.Exception.Message)" 'WARN'
    }
    # The LIMITED scheduled task is an independent non-admin path. Try it even when
    # CreateProcessWithTokenW returns false (including access denied / win32=5).
    if (Start-ProcessViaLaunchTask -FilePath $FilePath -ArgumentList $ArgumentList) {
        if (Test-EditorProcessEvidence -FilePath $FilePath -ArgumentList $ArgumentList -TimeoutMs $evidenceMsTask) {
            Write-EditorLaunchLog 'PROC_START_OK: mode=elevated_launch_task' 'DEBUG'
            return $true
        }
        Write-EditorLaunchLog 'PROC_START_FAIL: mode=elevated_launch_task no_process' 'WARN'
    } else {
        Write-EditorLaunchLog 'PROC_START_FAIL: mode=elevated_launch_task schtasks_failed' 'WARN'
    }
    # Last resort: start from the elevated token via DIRECT Start-Process (not cmd Quiet wrap -
    # Quiet breaks Electron warm IPC handoff). Prefer interactive NonElevated/Task paths above.
    try {
        Write-EditorLaunchLog 'PROC_START: mode=elevated_direct_fallback' 'DEBUG'
        Start-EditorProcessDirect -FilePath $FilePath -ArgumentList $ArgumentList | Out-Null
        if (Test-EditorProcessEvidence -FilePath $FilePath -ArgumentList $ArgumentList -TimeoutMs $evidenceMsDirect) {
            Write-EditorLaunchLog 'PROC_START_OK: mode=elevated_direct_fallback' 'DEBUG'
            return $true
        }
        Write-EditorLaunchLog 'PROC_START_FAIL: mode=elevated_direct_fallback no_process' 'ERROR'
    } catch {
        Write-EditorLaunchLog "PROC_START_FAIL: mode=elevated_direct_fallback ex=$($_.Exception.Message)" 'ERROR'
    }
    return $false
}

$script:EditorCimCache = @{}
$script:EditorCimCacheTtlSec = 2
$script:LaunchCimCallCount = 0
$script:VerboseLaunch = ($env:CLAUDE_CONNECT_VERBOSE_LAUNCH -eq '1')

function Clear-CursorProcessCache {
    $script:EditorCimCache = @{}
}

function Test-LaunchPerfEnabled {
    if (Get-Command Test-ConnectPerfEnabled -ErrorAction SilentlyContinue) {
        return [bool](Test-ConnectPerfEnabled)
    }
    # Keep the standalone fallback aligned with connect-ui.ps1: PERF is opt-in.
    return ($env:CLAUDE_CONNECT_PERF_LOG -eq '1')
}

function Write-LaunchPerfLog {
    param(
        [Parameter(Mandatory)][string]$Mark,
        [Parameter(Mandatory)][int]$Ms,
        [string]$Extra = ''
    )
    if (-not (Test-LaunchPerfEnabled)) { return }
    $cim = if ($null -ne $script:LaunchCimCallCount) { $script:LaunchCimCallCount } else { 0 }
    $fullExtra = "cim_total=$cim" + $(if ($Extra) { " $Extra" } else { '' })
    if (Get-Command Write-ConnectPerfLog -ErrorAction SilentlyContinue) {
        Write-ConnectPerfLog -Mark $Mark -Ms $Ms -Extra $fullExtra
    } else {
        Write-EditorLaunchLog "PERF[$Mark] ms=$Ms $fullExtra" 'DEBUG'
    }
}

function Invoke-CimEditorProcessQuery {
    param(
        [Parameter(Mandatory)][string]$ExeName,
        [string]$Reason = 'unspecified',
        [switch]$ForceRefresh
    )
    if ($null -eq $script:LaunchCimCallCount) { $script:LaunchCimCallCount = 0 }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    # Bug 48: TTL so closed editors are detected (cache must expire).
    if (-not $script:EditorCimCacheTtlSec) { $script:EditorCimCacheTtlSec = 2 }
    if (-not $ForceRefresh -and $script:EditorCimCache.ContainsKey($ExeName)) {
        $entry = $script:EditorCimCache[$ExeName]
        $cached = $null
        $ageOk = $false
        if ($entry -is [hashtable] -and $entry.ContainsKey('At') -and $entry.ContainsKey('Procs')) {
            $ageOk = ((Get-Date) - [datetime]$entry.At).TotalSeconds -lt [double]$script:EditorCimCacheTtlSec
            $cached = @($entry.Procs)
        } else {
            # Legacy bare array entry - treat as expired.
            $cached = @($entry)
            $ageOk = $false
        }
        if ($ageOk) {
            $sw.Stop()
            Write-LaunchPerfLog -Mark 'cim_query' -Ms $sw.ElapsedMilliseconds -Extra "reason=$Reason count=$($cached.Count) cache_hit=1 exe=$ExeName"
            return $cached
        }
    }
    $result = @(Get-CimInstance Win32_Process -Filter "Name='$ExeName'" -Property ProcessId,Name,CommandLine -ErrorAction SilentlyContinue)
    $script:EditorCimCache[$ExeName] = @{ At = Get-Date; Procs = $result }
    $script:LaunchCimCallCount++
    $sw.Stop()
    Write-LaunchPerfLog -Mark 'cim_query' -Ms $sw.ElapsedMilliseconds -Extra "reason=$Reason count=$($result.Count) cache_hit=0 exe=$ExeName"
    return $result
}

function Invoke-CimCursorProcessQuery {
    param(
        [string]$Reason = 'unspecified',
        [switch]$ForceRefresh
    )
    return @(Invoke-CimEditorProcessQuery -ExeName 'Cursor.exe' -Reason $Reason -ForceRefresh:$ForceRefresh)
}

function Get-CursorProfileProcesses {
    param(
        [string]$ProfileDir = (Get-CursorRemoteProfileDir),
        [switch]$ForceRefresh
    )
    if (-not $ProfileDir) { return @() }
    $needle = [regex]::Escape($ProfileDir)
    return @(Invoke-CimCursorProcessQuery -Reason 'profile_procs' -ForceRefresh:$ForceRefresh |
        Where-Object { $_.CommandLine -and ($_.CommandLine -match $needle) })
}

function Test-PathNeedleBoundaryMatch {
    # Boundary-safe substring check: NeedleEscaped must match exactly, or be immediately
    # followed by a path separator / quote character / whitespace, or end-of-string. A bare
    # substring test wrongly matches a shorter project path inside a longer one that shares the
    # same prefix (e.g. ".../ai-gap" incorrectly matching inside ".../ai-gap-summay"). Whitespace
    # must be in the allowed boundary set too: the OS-reported CommandLine for a Cursor process
    # can have a trailing/inter-argument space right after the path, which is not one of
    # \/"' or end-of-string - confirmed live (a real --folder-uri process had a trailing space
    # after the path and this check false-negatived, breaking on-folder detection).
    param(
        [string]$CommandLine,
        [Parameter(Mandatory)][string]$NeedleEscaped
    )
    if (-not $CommandLine) { return $false }
    return [bool]($CommandLine -match "$NeedleEscaped(?:[\\/`"'\s]|$)")
}

# .NET Process.MainWindowHandle / .MainWindowTitle only ever reflect ONE window per
# process - specifically whichever top-level window of that process is currently topmost
# in the system-wide Z-order. Cursor is a single-instance Electron app: all windows that
# share the ClaudeServerCursorProfile profile live inside ONE OS process, and when Cursor's
# IPC opens a brand-new window for a different project in that same already-running
# process, MainWindowHandle/MainWindowTitle keep reporting whichever window was already
# topmost (typically the pre-existing one) - the new window is completely invisible to any
# check built only on those two properties, even though it is a real, valid top-level
# window of the target PID. EnumWindows walks every top-level window on the desktop
# directly, so filtering by owning PID finds ALL of a process's windows, not just the
# Z-order-topmost one.
function Initialize-Win32WindowEnum {
    if ($script:Win32WindowEnumReady) { return }
    if (-not ('ClaudeConnectWin32Window' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class ClaudeConnectWin32Window
{
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern int GetWindowThreadProcessId(IntPtr hWnd, out int lpdwProcessId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern bool AttachThreadInput(int idAttach, int idAttachTo, bool fAttach);

    [DllImport("kernel32.dll")]
    public static extern int GetCurrentThreadId();
}
'@ -ErrorAction Stop
    }
    $script:Win32WindowEnumReady = $true
}

function Get-ProcessTopLevelWindows {
    # Returns EVERY top-level window owned by $ProcessId (visible or not), not just the
    # single Z-order-topmost one .NET's Process class exposes. Safe to call for a dead/
    # missing PID - EnumWindows simply yields zero matches, no exception.
    param(
        [Parameter(Mandatory)][int]$ProcessId
    )
    Initialize-Win32WindowEnum
    $results = [System.Collections.Generic.List[object]]::new()
    $callback = {
        param([IntPtr]$hWnd, [IntPtr]$lParam)
        $wpid = 0
        [void][ClaudeConnectWin32Window]::GetWindowThreadProcessId($hWnd, [ref]$wpid)
        if ($wpid -eq $ProcessId) {
            $title = ''
            $len = [ClaudeConnectWin32Window]::GetWindowTextLength($hWnd)
            if ($len -gt 0) {
                $sb = New-Object System.Text.StringBuilder ($len + 1)
                [void][ClaudeConnectWin32Window]::GetWindowText($hWnd, $sb, $sb.Capacity)
                $title = $sb.ToString()
            }
            $visible = [bool]([ClaudeConnectWin32Window]::IsWindowVisible($hWnd))
            $results.Add([PSCustomObject]@{ Hwnd = $hWnd; Title = $title; Visible = $visible })
        }
        return $true
    }
    try {
        [void][ClaudeConnectWin32Window]::EnumWindows($callback, [IntPtr]::Zero)
    } catch {
        if (Get-Command Write-EditorLaunchLog -ErrorAction SilentlyContinue) {
            Write-EditorLaunchLog "WIN32_ENUM_WINDOWS_FAIL: pid=$ProcessId error=$($_.Exception.Message)" 'WARN'
        }
    }
    return @($results)
}

# Bug 10 fix (2026-07-24, live repro): Cursor is launched via a background Scheduled Task
# ("LIMITED" task, commit b394340) or a detached process, neither of which is the current
# foreground app, so Windows' anti focus-stealing protection denies the new/detected window
# SetForegroundWindow rights by default - the window opens but stays behind other windows or
# minimized in the taskbar, and the user has to manually alt-tab to find it. A plain
# SetForegroundWindow call from a background PowerShell process is silently ignored by Windows
# for the same reason. The standard, documented workaround (AttachThreadInput) temporarily
# attaches our calling thread's input queue to whichever thread currently owns the real
# foreground window, which grants us the right to move foreground focus - this is the
# conventional technique for this exact "background process must foreground someone else's
# window" scenario (no legitimate Win32 API exists to unconditionally force foreground from a
# background process; AttachThreadInput is the sanctioned indirect route).
function Set-CursorWindowForeground {
    param([Parameter(Mandatory)][System.IntPtr]$Hwnd)
    Initialize-Win32WindowEnum
    try {
        if ([ClaudeConnectWin32Window]::IsIconic($Hwnd)) {
            [void][ClaudeConnectWin32Window]::ShowWindow($Hwnd, 9)  # SW_RESTORE
        }
        $fgHwnd = [ClaudeConnectWin32Window]::GetForegroundWindow()
        $fgPid = 0
        $fgThreadId = [ClaudeConnectWin32Window]::GetWindowThreadProcessId($fgHwnd, [ref]$fgPid)
        $targetPid = 0
        $targetThreadId = [ClaudeConnectWin32Window]::GetWindowThreadProcessId($Hwnd, [ref]$targetPid)
        $attached = $false
        if ($fgThreadId -ne 0 -and $targetThreadId -ne 0 -and $fgThreadId -ne $targetThreadId) {
            $attached = [bool][ClaudeConnectWin32Window]::AttachThreadInput($targetThreadId, $fgThreadId, $true)
        }
        try {
            $ok = [bool][ClaudeConnectWin32Window]::SetForegroundWindow($Hwnd)
        } finally {
            if ($attached) { [void][ClaudeConnectWin32Window]::AttachThreadInput($targetThreadId, $fgThreadId, $false) }
        }
        return $ok
    } catch {
        if (Get-Command Write-EditorLaunchLog -ErrorAction SilentlyContinue) {
            Write-EditorLaunchLog "SET_FOREGROUND_FAIL: error=$($_.Exception.Message)" 'WARN'
        }
        return $false
    }
}
# #endregion

function Get-RemoteEditorProcesses {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath,
        [switch]$ForceRefresh
    )
    $exe = if ($EditorCmd -eq 'cursor') { 'Cursor.exe' } else { 'Code.exe' }
    $uriNeedle = "ssh-remote+${Alias}"
    $pathNeedle = $RemotePath.TrimEnd('/')
    $pathNeedleEsc = [regex]::Escape($pathNeedle)
    $profileDir = if ($EditorCmd -eq 'cursor') { Get-CursorRemoteProfileDir } elseif ($EditorCmd -eq 'code') { Get-CodeRemoteProfileDir } else { $null }

    $matches = @(Invoke-CimEditorProcessQuery -ExeName $exe -Reason 'remote_editor_procs' -ForceRefresh:$ForceRefresh |
        Where-Object {
            $cmd = $_.CommandLine
            if (-not $cmd) { return $false }
            if (-not (Test-PathNeedleBoundaryMatch -CommandLine $cmd -NeedleEscaped $pathNeedleEsc)) { return $false }
            if ($cmd -match [regex]::Escape($uriNeedle)) { return $true }
            if ($profileDir -and ($cmd -match [regex]::Escape($profileDir))) { return $true }
            return $false
        })
    return $matches
}

function Test-RemoteEditorWindowOpen {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath
    )
    # Auth gate: on correct folder AND a visible process with uri/path match.
    if (-not (Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)) {
        return $false
    }
    return (Test-RemoteEditorWindowOpenWhenOnFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)
}

function Test-RemoteEditorWindowOpenWhenOnFolder {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath
    )
    foreach ($p in @(Get-RemoteEditorProcesses -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)) {
        try {
            $wp = [System.Diagnostics.Process]::GetProcessById($p.ProcessId)
            if ($wp.MainWindowHandle -ne [IntPtr]::Zero) {
                Request-CursorWindowForegroundOnce -RemotePath $RemotePath -Hwnd $wp.MainWindowHandle
                return $true
            }
        } catch {}
    }
    if ($EditorCmd -eq 'cursor') {
        foreach ($p in @(Get-CursorMainProfileProcesses)) {
            try {
                $wp = [System.Diagnostics.Process]::GetProcessById($p.ProcessId)
                if ($wp.MainWindowHandle -ne [IntPtr]::Zero) {
                    Request-CursorWindowForegroundOnce -RemotePath $RemotePath -Hwnd $wp.MainWindowHandle
                    return $true
                }
            } catch {}
        }
    }
    return $false
}

# Bug 10 fix: foreground the confirmed-open window exactly once per RemotePath (not on every
# poll tick) - repeated SetForegroundWindow calls while the user is deliberately working in a
# different app would be its own annoyance, so only steal focus the first time this specific
# project's window is confirmed open after a launch.
function Request-CursorWindowForegroundOnce {
    param(
        [Parameter(Mandatory)][string]$RemotePath,
        [Parameter(Mandatory)][System.IntPtr]$Hwnd
    )
    if (-not $script:CursorForegroundedForPath) { $script:CursorForegroundedForPath = @{} }
    if ($script:CursorForegroundedForPath.ContainsKey($RemotePath)) { return }
    $script:CursorForegroundedForPath[$RemotePath] = $true
    $ok = Set-CursorWindowForeground -Hwnd $Hwnd
    if (Get-Command Write-EditorLaunchLog -ErrorAction SilentlyContinue) {
        Write-EditorLaunchLog "SET_FOREGROUND: path=$RemotePath ok=$ok" 'INFO'
    }
}

function Get-RemoteFolderUri {
    param(
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath
    )
    $path = $RemotePath.TrimEnd('/')
    return "vscode-remote://ssh-remote+${Alias}${path}"
}

function Get-CursorMainProfileProcesses {
    param([string]$ProfileDir = (Get-CursorRemoteProfileDir))
    return @(Get-CursorProfileProcesses -ProfileDir $ProfileDir |
        Where-Object { $_.CommandLine -and ($_.CommandLine -notmatch '--type=') })
}

function Get-CursorMainPersonalProcesses {
    param(
        [string]$ProfileDir = (Get-CursorRemoteProfileDir),
        [switch]$ForceRefresh
    )
    if (-not $ProfileDir) { return @() }
    $profileEsc = [regex]::Escape($ProfileDir)
    return @(Invoke-CimCursorProcessQuery -Reason 'personal_procs' -ForceRefresh:$ForceRefresh |
        Where-Object {
            $_.CommandLine -and ($_.CommandLine -notmatch $profileEsc) -and ($_.CommandLine -notmatch '--type=')
        })
}

function Test-PersonalCursorDominant {
    $personalMain = @(Get-CursorMainPersonalProcesses).Count
    $profileMain = @(Get-CursorMainProfileProcesses).Count
    return ($personalMain -ge 3 -and $profileMain -eq 0)
}

function Test-CursorWindowTitleIsAgentHome {
    param(
        [string]$Title,
        [string]$ProjectRootName = ''
    )
    if (-not $Title) { return $false }
    # If the title shows THIS project at the template-anchored position, it is a real project window,
    # not the agent-home splash. Use the anchored matcher (not a bare substring) so the "Smart" site
    # tag / prefix siblings do not spoof a project match.
    if ($ProjectRootName -and (Test-CursorWindowTitleMatchesProject -Title $Title -RootName $ProjectRootName)) {
        return $false
    }
    if ($Title -match '(?i)^cursor agents$|cursor agents\b|agent home') { return $true }
    return $false
}

function Test-CursorWindowShowsAgentHome {
    param(
        [Parameter(Mandatory)][int]$ProcessId,
        [string]$RemotePath = ''
    )
    $rootName = ''
    if ($RemotePath) { $rootName = ($RemotePath.TrimEnd('/') -split '/')[-1] }
    try {
        $wp = [System.Diagnostics.Process]::GetProcessById($ProcessId)
        return (Test-CursorWindowTitleIsAgentHome -Title $wp.MainWindowTitle -ProjectRootName $rootName)
    } catch { }
    return $false
}

function Test-RemoteEditorOnCorrectFolder {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath
    )
    if ($EditorCmd -ne 'cursor') {
        return (Test-RemoteEditorProcesses -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath).Count -gt 0
    }
    # NOTE: intentionally NO global "if (Test-RemoteEditorInAgentHome) return false" short-circuit here.
    # A standalone "Cursor Agents" window is normal in Cursor 3.x and coexists with real project windows;
    # the old global veto made on_folder=false for EVERY project whenever any agent-home window existed,
    # which blocked launch success and triggered the "drifted to Agent/home" relaunch loop even though the
    # project WAS open. Per-window agent-home is still checked below (only a window that BOTH matches this
    # project AND is itself on agent-home is rejected), which is the correct, project-scoped test.
    $uri = Get-RemoteFolderUri -Alias $Alias -RemotePath $RemotePath
    $pathNeedle = [regex]::Escape($RemotePath.TrimEnd('/'))
    $aliasNeedle = [regex]::Escape("ssh-remote+${Alias}")
    $uriNeedle = [regex]::Escape($uri)
    $rootName = ($RemotePath.TrimEnd('/') -split '/')[-1]
    $rootNeedle = if ($rootName) { [regex]::Escape($rootName) } else { '' }
    $titleTag = Get-CursorWindowTitleTag
    $aliasOnlyNeedle = [regex]::Escape($Alias)
    foreach ($p in @(Get-CursorMainProfileProcesses)) {
        $cmd = $p.CommandLine
        if ($cmd) {
            if (Test-PathNeedleBoundaryMatch -CommandLine $cmd -NeedleEscaped $uriNeedle) {
                if (-not (Test-CursorWindowShowsAgentHome -ProcessId $p.ProcessId -RemotePath $RemotePath)) {
                    return $true
                }
                continue
            }
            if ($cmd -match $aliasNeedle -and (Test-PathNeedleBoundaryMatch -CommandLine $cmd -NeedleEscaped $pathNeedle)) {
                if (-not (Test-CursorWindowShowsAgentHome -ProcessId $p.ProcessId -RemotePath $RemotePath)) {
                    return $true
                }
                continue
            }
        }
        if ($rootNeedle) {
            # H11_multi_window_enum: MainWindowTitle alone is the Z-order-topmost window of
            # this PID ONLY - when another project's window is already open+focused on this
            # shared profile process, MainWindowTitle keeps returning THAT window's title
            # forever and this check would never see a genuinely-opened window for a
            # different project hosted in the very same process. Enumerate every top-level
            # window actually owned by the PID and apply the exact same title-match rule to
            # each one. This is strictly a superset of the single-window check (the previous
            # MainWindowTitle is itself always one of the enumerated windows), so it can only
            # ADD matches the old check missed - it cannot cause a false positive that the
            # single-window check would not also have produced.
            foreach ($win in @(Get-ProcessTopLevelWindows -ProcessId $p.ProcessId)) {
                $title = $win.Title
                # Accept either our custom "[Claude Server <Site>] <root>" title template or Cursor's
                # own default Remote-SSH title "... [SSH: <alias>] - Cursor". Match the root ONLY at the
                # template-anchored position (never anywhere in the title) so project "smart" does not
                # match the "Smart" in the site tag, nor "smartdesk"/prefix siblings.
                if (Test-CursorWindowTitleMatchesProject -Title $title -RootName $rootName -TitleTag $titleTag -AliasNeedleEscaped $aliasOnlyNeedle) {
                    return $true
                }
            }
        }
    }
    return $false
}

function Get-RemoteEditorSessionPresence {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath
    )
    # Bug 60: single-pass on_folder + window_open (one CIM walk via shared cache).
    $onFolder = $false
    $windowOpen = $false
    if ($EditorCmd -ne 'cursor') {
        $matched = @(Get-RemoteEditorProcesses -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)
        $onFolder = ($matched.Count -gt 0)
        foreach ($p in $matched) {
            try {
                $wp = [System.Diagnostics.Process]::GetProcessById($p.ProcessId)
                if ($wp.MainWindowHandle -ne [IntPtr]::Zero) { $windowOpen = $true; break }
            } catch { }
        }
        return [pscustomobject]@{ OnFolder = [bool]$onFolder; WindowOpen = [bool]$windowOpen }
    }
    # OnFolder MUST match Test-RemoteEditorOnCorrectFolder (multi-window title enum). The old
    # version short-circuited on Test-RemoteEditorInAgentHome (standalone Agents window poisoned
    # every project) AND only inspected MainWindowTitle (Z-order-topmost of the shared PID), so
    # when refactoreoldclub was focused and dakhl was open in a second window of the SAME process,
    # presence.OnFolder stayed False forever even though on_folder=True - connect status showed
    # "agent" / "Opening Cursor failed" while the project window was visibly open (live 2026-07-25).
    $onFolder = Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath
    foreach ($p in @(Get-CursorMainProfileProcesses)) {
        foreach ($win in @(Get-ProcessTopLevelWindows -ProcessId $p.ProcessId)) {
            if ($win.Title) { $windowOpen = $true; break }
        }
        if ($windowOpen) { break }
        try {
            $wp = [System.Diagnostics.Process]::GetProcessById($p.ProcessId)
            if ($wp.MainWindowHandle -ne [IntPtr]::Zero) { $windowOpen = $true; break }
        } catch { }
    }
    return [pscustomobject]@{ OnFolder = [bool]$onFolder; WindowOpen = [bool]$windowOpen }
}

function Get-RemoteEditorStateExplain {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath
    )
    $bits = @()
    $uri = Get-RemoteFolderUri -Alias $Alias -RemotePath $RemotePath
    $path = $RemotePath.TrimEnd('/')
    $bits += "target_uri=$uri target_path=$path"

    if ($EditorCmd -ne 'cursor') {
        $matched = @(Get-RemoteEditorProcesses -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)
        $bits += "editor=$EditorCmd matched_procs=$($matched.Count) on_folder=$($matched.Count -gt 0)"
        return ($bits -join ' | ')
    }

    $profileDir = Get-CursorRemoteProfileDir
    $mains = @(Get-CursorMainProfileProcesses)
    $allProfile = @(Get-CursorProfileProcesses)
    $allCursor = @(Invoke-CimCursorProcessQuery -Reason 'state_explain_all')
    $personalCount = @($allCursor | Where-Object {
        $_.CommandLine -and ($_.CommandLine -notmatch [regex]::Escape($profileDir))
    }).Count
    $bits += "cursor_total=$($allCursor.Count) profile_total=$($allProfile.Count) profile_main=$($mains.Count) personal_main=$personalCount"

    $agentHome = Test-RemoteEditorInAgentHome -RemotePath $RemotePath
    $bits += "agent_home=$agentHome"
    if ($agentHome) {
        foreach ($p in $mains) {
            $cmd = $p.CommandLine
            if (-not $cmd) {
                $bits += "agent_reason pid=$($p.ProcessId) empty_cmdline"
                continue
            }
            if ($cmd -notmatch 'folder-uri') {
                $bits += "agent_reason pid=$($p.ProcessId) no_folder_uri_in_cmd"
            } elseif (Test-CursorWindowShowsAgentHome -ProcessId $p.ProcessId -RemotePath $RemotePath) {
                $bits += "agent_reason pid=$($p.ProcessId) folder_uri_ignored_title_agents"
            }
        }
    }

    $pathNeedle = [regex]::Escape($path)
    $aliasNeedle = [regex]::Escape("ssh-remote+${Alias}")
    $uriNeedle = [regex]::Escape($uri)
    $rootName = ($path -split '/')[-1]
    $rootNeedle = if ($rootName) { [regex]::Escape($rootName) } else { '' }
    $titleTag = Get-CursorWindowTitleTag
    $aliasOnlyNeedle = [regex]::Escape($Alias)
    $onFolder = $false
    foreach ($p in $mains) {
        $cmd = $p.CommandLine
        if (-not $cmd) {
            $bits += "main pid=$($p.ProcessId) empty_cmdline"
            continue
        }
        $uriHit = Test-PathNeedleBoundaryMatch -CommandLine $cmd -NeedleEscaped $uriNeedle
        $rawAliasMatch = [bool]($cmd -match $aliasNeedle)
        $boundaryPathMatch = [bool](Test-PathNeedleBoundaryMatch -CommandLine $cmd -NeedleEscaped $pathNeedle)
        $aliasPathHit = $rawAliasMatch -and $boundaryPathMatch
        $titleHit = $false
        $title = ''
        try {
            $wp = [System.Diagnostics.Process]::GetProcessById($p.ProcessId)
            $title = $wp.MainWindowTitle
            if ($rootNeedle -and (Test-CursorWindowTitleMatchesProject -Title $title -RootName $rootName -TitleTag $titleTag -AliasNeedleEscaped $aliasOnlyNeedle)) {
                $titleHit = $true
            }
        } catch { }
        $bits += (
            "main pid=$($p.ProcessId) uri_hit=$uriHit alias_path_hit=$aliasPathHit title_hit=$titleHit " +
            "title=$title cmd=$(Format-EditorProcessCommandLine -CommandLine $cmd -MaxLen 180)"
        )
        if ($uriHit -or $aliasPathHit) {
            if (-not (Test-CursorWindowShowsAgentHome -ProcessId $p.ProcessId -RemotePath $RemotePath)) {
                $onFolder = $true
            }
        }
        if ($titleHit) { $onFolder = $true }
    }
    if ($mains.Count -eq 0) {
        $bits += 'folder_reason=no_profile_main_process'
    } elseif (-not $onFolder) {
        $bits += 'folder_reason=no_main_process_matched_uri_alias_or_title'
    }
    $bits += "on_folder=$onFolder window_open=$(Test-RemoteEditorWindowOpen -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)"
    return ($bits -join ' | ')
}

function Write-EditorLaunchVerboseState {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath,
        [switch]$IncludeSnapshot,
        [switch]$ForceLog
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $alwaysLog = $ForceLog -or $Label -match '^EXHAUSTED' -or $script:VerboseLaunch
    if (-not $alwaysLog) {
        $sw.Stop()
        Write-LaunchPerfLog -Mark "verbose_$Label" -Ms $sw.ElapsedMilliseconds -Extra 'skipped=gated'
        return
    }
    Write-EditorLaunchLog "STATE[$Label] $(Get-RemoteEditorStateExplain -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)" 'DEBUG'
    Write-EditorLaunchLog "DIAG[$Label] $(Get-RemoteEditorLaunchDiag -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)" 'DEBUG'
    Write-EditorLaunchLog "DETECT[$Label] $(Get-RemoteEditorDetectionDiag -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)" 'DEBUG'
    if ($EditorCmd -eq 'cursor') {
        Write-EditorLaunchLog "STORAGE[$Label] $(Get-CursorProfileStorageDiag)" 'DEBUG'
    }
    if ($IncludeSnapshot -and ($script:VerboseLaunch -or $ForceLog)) {
        Write-EditorLaunchSnapshot -Label $Label -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath
    }
    $sw.Stop()
    Write-LaunchPerfLog -Mark "verbose_$Label" -Ms $sw.ElapsedMilliseconds -Extra "snapshot=$([bool]$IncludeSnapshot)"
}

function Test-RemoteEditorInAgentHome {
    param(
        [string]$ProfileDir = (Get-CursorRemoteProfileDir),
        [string]$RemotePath = ''
    )
    foreach ($p in @(Get-CursorMainProfileProcesses -ProfileDir $ProfileDir)) {
        $cmd = $p.CommandLine
        if (-not $cmd) { continue }
        # Agent/home title wins even when folder-uri is present (Cursor 3.x forum #153009).
        if (Test-CursorWindowShowsAgentHome -ProcessId $p.ProcessId -RemotePath $RemotePath) { return $true }
        # A main process opens a folder via EITHER --folder-uri=... OR --remote ssh-remote+<alias> <path>
        # (equivalently a vscode-remote:// uri). The cmd-line fallback below must only flag agent-home
        # when the launch opened NO folder at all - otherwise the --remote-first strategy (the reliable
        # warm-handoff path) is misread as agent-home on EVERY poll, and the success gate (-not agent_home)
        # rejects every launch even though the window actually opened. Live regression 2026-07-25: after
        # reordering strategies to --remote first, project windows never "succeeded" (agent_home=True stuck).
        $opensFolder = ($cmd -match 'folder-uri') -or ($cmd -match '(?i)(^|\s)--remote(\s|=)') -or ($cmd -match 'ssh-remote\+') -or ($cmd -match 'vscode-remote://')
        if (-not $opensFolder) {
            $title = ''
            try {
                $wp = [System.Diagnostics.Process]::GetProcessById($p.ProcessId)
                $title = [string]$wp.MainWindowTitle
            } catch { }
            # Settings (and similar) often lack a folder - do not treat as agent-home.
            if ($title -match '(?i)settings') { continue }
            return $true
        }
    }
    return $false
}

function Write-EditorLaunchLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'TRACE')][string]$Level = 'INFO'
    )
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog $Message $Level
    }
}

function Get-CursorProfileStorageDiag {
    $profileDir = Get-CursorRemoteProfileDir
    $gs = Join-Path $profileDir 'User\globalStorage'
    $ws = Join-Path $profileDir 'User\workspaceStorage'
    $db = Join-Path $gs 'state.vscdb'
    $storageJson = Join-Path $gs 'storage.json'
    $wsCount = 0
    if (Test-Path $ws) { $wsCount = @(Get-ChildItem -Path $ws -Directory -ErrorAction SilentlyContinue).Count }
    $dbSize = if (Test-Path $db) { (Get-Item $db).Length } else { 0 }
    $walSize = if (Test-Path "$db-wal") { (Get-Item "$db-wal").Length } else { 0 }
    $recent = ''
    if (Test-Path $storageJson) {
        try {
            $sj = Get-Content $storageJson -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($sj.'telemetry.machineId') { $recent += " machineId=set" }
        } catch { $recent = 'storage_json_read_error' }
    }
    return (
        "profile_dir=$profileDir globalStorage_exists=$(Test-Path $gs) state_vscdb=$dbSize wal=$walSize " +
        "workspaceStorage_dirs=$wsCount$recent"
    )
}

function Get-ForegroundWindowTitle {
    try {
        if (-not ('Win32.ForegroundWindow' -as [type])) {
            Add-Type -Name ForegroundWindow -Namespace Win32 -MemberDefinition @'
[DllImport("user32.dll")] public static extern System.IntPtr GetForegroundWindow();
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(System.IntPtr hWnd, System.Text.StringBuilder text, int count);
'@ -ErrorAction Stop
        }
        $hwnd = [Win32.ForegroundWindow]::GetForegroundWindow()
        if ($hwnd -eq [IntPtr]::Zero) { return '' }
        $sb = New-Object System.Text.StringBuilder 512
        [void][Win32.ForegroundWindow]::GetWindowText($hwnd, $sb, $sb.Capacity)
        return $sb.ToString()
    } catch {
        return ''
    }
}

function Get-RemoteEditorLaunchDiag {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath
    )
    $uri = Get-RemoteFolderUri -Alias $Alias -RemotePath $RemotePath
    $onFolder = Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath
    $agentHome = if ($EditorCmd -eq 'cursor') { Test-RemoteEditorInAgentHome -RemotePath $RemotePath } else { $false }
    $windowOpen = Test-RemoteEditorWindowOpen -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath
    $foregroundTitle = Get-ForegroundWindowTitle
    $mains = if ($EditorCmd -eq 'cursor') { @(Get-CursorMainProfileProcesses) } else { @() }
    $mainSummaries = @()
    foreach ($p in $mains) {
        $cmd = $p.CommandLine
        if (-not $cmd) { $cmd = '' }
        $hasUri = $cmd -match 'folder-uri'
        $hasRemote = $cmd -match '--remote'
        $hasClassic = $cmd -match '--classic'
        $hasPath = $cmd -match [regex]::Escape($RemotePath.TrimEnd('/'))
        if ($cmd.Length -gt 160) { $cmd = $cmd.Substring(0, 160) + '...' }
        $mainSummaries += "pid=$($p.ProcessId) uri=$hasUri remote=$hasRemote classic=$hasClassic path=$hasPath cmd=$cmd"
    }
    $mainText = if ($mainSummaries.Count -gt 0) { ($mainSummaries -join ' | ') } else { 'none' }
    return (
        "expected_uri=$uri on_folder=$onFolder agent_home=$agentHome window_open=$windowOpen " +
        "foreground_title=$foregroundTitle main_count=$($mains.Count) main=[$mainText]"
    )
}


function Get-CursorProxyLaunchArgs {
    # Chromium/Electron flags: settings.json alone is not enough on Cursor 3.9.x
    # Prefer sticky sidecar front door (18999) when listening AND backend -L is up.
    # Last resort: no --proxy-server (server_direct / none_direct) so Cursor is not
    # stuck on a dead 18998/18999 loopback proxy.
    $port = 0
    $mode = 'none_direct'
    $front = 0
    if ($script:CursorSocksFrontPort) { $front = [int]$script:CursorSocksFrontPort }
    $frontUp = $false
    if ($front -gt 0) {
        if (Get-Command Test-LocalPortOpen -ErrorAction SilentlyContinue) {
            $frontUp = [bool](Test-LocalPortOpen -PortNum $front)
        } elseif (Get-Command Test-CursorProxySidecarListening -ErrorAction SilentlyContinue) {
            $frontUp = [bool](Test-CursorProxySidecarListening -Port $front)
        }
    }
    $backSocks = 0
    if ($script:SocksProxyPort) { $backSocks = [int]$script:SocksProxyPort }
    $backUp = $false
    if ($backSocks -gt 0) {
        if (Get-Command Test-LocalPortOpen -ErrorAction SilentlyContinue) {
            $backUp = [bool](Test-LocalPortOpen -PortNum $backSocks)
        } else {
            $backUp = $true
        }
    }
    if ($frontUp -and $front -gt 0 -and $backUp) {
        $port = $front
        $mode = 'sidecar'
    } elseif ($backUp -and $backSocks -gt 0) {
        $port = $backSocks
        $mode = 'xray'
    }
    if ($port -le 0) {
        if (Get-Command Get-CursorProxyMode -ErrorAction SilentlyContinue) {
            try { $mode = Get-CursorProxyMode } catch { $mode = 'server_direct' }
        } else {
            $mode = 'server_direct'
        }
        if ($mode -ne 'server_direct' -and $mode -ne 'none_direct') { $mode = 'server_direct' }
        Write-EditorLaunchLog ("LAUNCH_PROXY mode={0}" -f $mode) 'INFO'
        return @()
    }
    Write-EditorLaunchLog ("LAUNCH_PROXY mode={0} socks={1}" -f $mode, $port) 'INFO'
    return @(
        "--proxy-server=socks5://127.0.0.1:$port",
        '--disable-http2'
    )
}

function Get-RemoteEditorLaunchStrategies {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath,
        [Parameter(Mandatory)][string]$Uri,
        [switch]$NewWindow,
        # When the shared profile already has windows open, ONLY try --remote. Live 2026-07-25:
        # cascading to remote-classic / folder-uri / folder-uri-classic within ~5s of the first
        # --remote IPC handoff interrupts Cursor mid-connect; the folder never settles, connect
        # reports LAUNCH_FAIL, then a SINGLE later --remote (manual) opens the project fine.
        # Warm handoff also often navigates the EXISTING window (title changes, window-count does
        # not) - folder-uri warm paths are known to land on Welcome and only make that worse.
        [switch]$WarmHandoff
    )
    $path = $RemotePath.TrimEnd('/')
    $remoteArg = "ssh-remote+${Alias}"
    $strategies = @()

    # Strategy ORDER matters. Live-verified 2026-07-25 (Cursor 3.x, Windows, warm instance):
    #
    #   --remote ssh-remote+<alias> <path>      -> opens the REAL folder in a new window, both
    #                                              cold AND when Cursor is already running (warm
    #                                              IPC handoff). Confirmed via screenshot: a fresh
    #                                              window loaded "<PROJECT> [SSH: <alias>]" in the
    #                                              explorer, not the Welcome/Agents splash.
    #   --folder-uri=vscode-remote://ssh-remote+.../<path>  -> works when Cursor is CLOSED, but on
    #                                              a warm handoff Cursor lands on the Welcome/Agents
    #                                              page and NEVER opens the folder (Cursor forum
    #                                              #153009, #165329; microsoft/vscode #209072). The
    #                                              '=' form survives Chromium's '://' arg filter but
    #                                              does NOT fix the warm-handoff welcome-page bug.
    #
    # So --remote MUST come first. It was previously last, behind folder-uri-classic/folder-uri,
    # so every warm launch (picking a 2nd/3rd project while a window is open) opened Welcome and
    # the real folder never loaded (project "smart"/"deploy" "did not open" reports 2026-07-25).
    # folder-uri variants are kept only as cold-start fallbacks. --classic is not needed for the
    # folder to open (the verified working invocation had no --classic) and is demoted to fallback.
    $folderUriArg = "--folder-uri=$Uri"

    if ($EditorCmd -eq 'cursor') {
        $profileDir = Get-CursorRemoteProfileDir
        $common = @('--user-data-dir', $profileDir)
        $common += @(Get-CursorProxyLaunchArgs)
        if ($NewWindow) { $common += '--new-window' }
        $strategies += [PSCustomObject]@{
            Name = 'remote'
            Args = $common + @('--remote', $remoteArg, $path)
        }
        if ($WarmHandoff) {
            # One strategy, long poll outside - do NOT cascade folder-uri / classic (interrupts IPC).
            return $strategies
        }
        $strategies += [PSCustomObject]@{
            Name = 'remote-classic'
            Args = $common + @('--classic', '--remote', $remoteArg, $path)
        }
        $strategies += [PSCustomObject]@{
            Name = 'folder-uri'
            Args = $common + @($folderUriArg)
        }
        $strategies += [PSCustomObject]@{
            Name = 'folder-uri-classic'
            Args = $common + @('--classic', $folderUriArg)
        }
        return $strategies
    }

    $profileDir = Get-CodeRemoteProfileDir
    $common = @('--user-data-dir', $profileDir)
    if ($NewWindow) { $common += '--new-window' }
    # --remote first (see cursor branch above): it opens the real folder on a warm handoff,
    # whereas --folder-uri lands on Welcome when the editor is already running.
    $strategies += [PSCustomObject]@{
        Name = 'remote'
        Args = $common + @('--remote', $remoteArg, $path)
    }
    $strategies += [PSCustomObject]@{
        Name = 'folder-uri'
        Args = $common + @($folderUriArg)
    }
    return $strategies
}

function Format-EditorProcessCommandLine {
    param(
        [string]$CommandLine,
        [int]$MaxLen = 220
    )
    if (-not $CommandLine) { return '' }
    if ($CommandLine.Length -le $MaxLen) { return $CommandLine }
    return $CommandLine.Substring(0, $MaxLen) + '...'
}

function Get-RemoteEditorProcessSnapshot {
    param(
        [string]$EditorCmd = 'cursor',
        [string]$Alias = '',
        [string]$RemotePath = ''
    )
    $lines = @()
    $lines += "snapshot_ts=$(Get-Date -Format 'o')"
    $lines += "elevated=$(Test-IsElevatedShell) interactive_user=$(Get-InteractiveWindowsUser)"
    if ($Alias -and $RemotePath) {
        $lines += "target_alias=$Alias target_path=$RemotePath target_uri=$(Get-RemoteFolderUri -Alias $Alias -RemotePath $RemotePath)"
        $lines += "detect_on_folder=$(Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)"
        if ($EditorCmd -eq 'cursor') {
            $lines += "detect_agent_home=$(Test-RemoteEditorInAgentHome -RemotePath $RemotePath)"
        }
        $lines += "detect_window_open=$(Test-RemoteEditorWindowOpen -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)"
    }

    if ($EditorCmd -eq 'cursor') {
        $profileDir = Get-CursorRemoteProfileDir
        $lines += "profile_dir=$profileDir profile_exists=$(Test-Path $profileDir)"
        $settingsPath = Join-Path $profileDir 'User\settings.json'
        $lines += "profile_settings_exists=$(Test-Path $settingsPath)"
        $lines += (Get-CursorProfileStorageDiag)
    }

    $exeName = if ($EditorCmd -eq 'cursor') { 'Cursor.exe' } else { 'Code.exe' }
    $all = @(Invoke-CimEditorProcessQuery -ExeName $exeName -Reason 'process_snapshot')
    $lines += "${exeName}_total=$($all.Count)"
    if ($EditorCmd -eq 'cursor') {
        $profileDir = Get-CursorRemoteProfileDir
        $profileCount = @($all | Where-Object { $_.CommandLine -and ($_.CommandLine -match [regex]::Escape($profileDir)) }).Count
        $personalCount = $all.Count - $profileCount
        $lines += "cursor_profile_procs=$profileCount cursor_personal_procs=$personalCount"
    }

    $idx = 0
    foreach ($p in $all) {
        $idx++
        $cmd = $p.CommandLine
        if (-not $cmd) { $cmd = '' }
        $procType = 'unknown'
        if ($cmd -match '--type=renderer') { $procType = 'renderer' }
        elseif ($cmd -match '--type=gpu-process') { $procType = 'gpu' }
        elseif ($cmd -match '--type=utility') { $procType = 'utility' }
        elseif ($cmd -notmatch '--type=') { $procType = 'main' }
        $isMain = ($procType -eq 'main')
        $isProfile = $false
        $hasFolderUri = $false
        $hasRemote = $false
        $hasClassic = $false
        $hasNewWindow = $false
        $hasUserData = $false
        $pathMatch = $false
        $aliasMatch = $false
        if ($EditorCmd -eq 'cursor') {
            $profileDir = Get-CursorRemoteProfileDir
            if ($profileDir -and $cmd -match [regex]::Escape($profileDir)) { $isProfile = $true }
        }
        if ($cmd -match '--folder-uri') { $hasFolderUri = $true }
        if ($cmd -match '--remote') { $hasRemote = $true }
        if ($cmd -match '--classic') { $hasClassic = $true }
        if ($cmd -match '--new-window') { $hasNewWindow = $true }
        if ($cmd -match '--user-data-dir') { $hasUserData = $true }
        if ($RemotePath -and $cmd -match [regex]::Escape($RemotePath.TrimEnd('/'))) { $pathMatch = $true }
        if ($Alias -and $cmd -match [regex]::Escape("ssh-remote+${Alias}")) { $aliasMatch = $true }
        $title = ''
        $hwnd = 0
        if ($isMain) {
            try {
                $wp = [System.Diagnostics.Process]::GetProcessById($p.ProcessId)
                $title = $wp.MainWindowTitle
                if ($wp.MainWindowHandle -ne [IntPtr]::Zero) { $hwnd = 1 }
            } catch { }
        }
        $lines += (
            "${exeName}#$idx pid=$($p.ProcessId) parent=$($p.ParentProcessId) type=$procType main=$isMain profile=$isProfile hwnd=$hwnd " +
            "folder_uri=$hasFolderUri remote=$hasRemote classic=$hasClassic new_window=$hasNewWindow " +
            "user_data=$hasUserData alias_match=$aliasMatch path_match=$pathMatch " +
            "title=$title cmd=$(Format-EditorProcessCommandLine -CommandLine $cmd)"
        )
    }
    return ($lines -join ' | ')
}

function Write-EditorLaunchSnapshot {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$EditorCmd,
        [string]$Alias = '',
        [string]$RemotePath = ''
    )
    Write-EditorLaunchLog "SNAPSHOT[$Label] $(Get-RemoteEditorProcessSnapshot -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)" 'DEBUG'
}

function Get-RemoteEditorDetectionDiag {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath
    )
    $matched = @(Get-RemoteEditorProcesses -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)
    $visible = 0
    $hwndZero = 0
    foreach ($p in $matched) {
        try {
            $wp = [System.Diagnostics.Process]::GetProcessById($p.ProcessId)
            if ($wp.MainWindowHandle -ne [IntPtr]::Zero) { $visible++ } else { $hwndZero++ }
        } catch { $hwndZero++ }
    }
    $profileCount = 0
    $profileVisible = 0
    if ($EditorCmd -eq 'cursor') {
        foreach ($p in @(Get-CursorProfileProcesses)) {
            $profileCount++
            try {
                $wp = [System.Diagnostics.Process]::GetProcessById($p.ProcessId)
                if ($wp.MainWindowHandle -ne [IntPtr]::Zero) { $profileVisible++ }
            } catch { }
        }
    }
    $pathTail = $RemotePath.TrimEnd('/')
    if ($pathTail.Length -gt 48) { $pathTail = '...' + $pathTail.Substring($pathTail.Length - 45) }
    return (
        "matched=$($matched.Count) visible=$visible hwnd0=$hwndZero " +
        "profile=$profileCount profile_visible=$profileVisible path=$pathTail"
    )
}

function Stop-RemoteEditor {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath
    )
    # Path/alias scoped only ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â never kills the whole ClaudeServerCursorProfile tree.
    $procs = @(Get-RemoteEditorProcesses -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)
    Write-EditorLaunchLog (
        "STOP_REMOTE_EDITOR: path_scoped_only alias=$Alias path=$RemotePath matched=$($procs.Count)"
    ) 'INFO'
    if ($procs.Count -eq 0) {
        Write-EditorLaunchLog 'STOP_REMOTE_EDITOR: no matching processes' 'DEBUG'
        return
    }

    foreach ($p in $procs) {
        try {
            $wp = [System.Diagnostics.Process]::GetProcessById($p.ProcessId)
            if ($wp.MainWindowHandle -ne [IntPtr]::Zero) {
                $null = $wp.CloseMainWindow()
            }
        } catch { }
    }
    $deadline = (Get-Date).AddSeconds(12)
    while ((Get-Date) -lt $deadline) {
        if (@(Get-RemoteEditorProcesses -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath).Count -eq 0) {
            return
        }
        Start-Sleep -Milliseconds 500
    }
    foreach ($p in @(Get-RemoteEditorProcesses -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)) {
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

function Get-CursorLaunchWindowPlan {
    # profile_all>0 with profile_main=False ("orphan helpers") means either helpers from
    # an existing/half-dead profile session, OR another concurrent connect session's window
    # that is still spinning up and not yet classified as "main" in this exact CIM snapshot.
    # Treat this the same as profile_open and request --new-window too - otherwise a race is
    # possible where a sibling connect session's window finishes appearing microseconds after
    # our entry-time check, and Cursor's single-instance IPC silently reroutes our "open
    # folder" request into THAT window instead of spawning ours (confirmed live: a launch can
    # spend minutes retrying/recovering while actually pointed at someone else's project).
    param(
        [Parameter(Mandatory)][bool]$AgentHome,
        [Parameter(Mandatory)][bool]$HasProfileWindow,
        [Parameter(Mandatory)][int]$ProfileProcCount
    )
    $orphanHelpers = ((-not $HasProfileWindow) -and ($ProfileProcCount -gt 0))
    $useNewWindow = ($AgentHome -or $HasProfileWindow -or $orphanHelpers)
    $reason = if ($AgentHome) { 'agent_home' } elseif ($HasProfileWindow) { 'profile_open' } elseif ($orphanHelpers) { 'orphan_helpers' } else { 'cold_start' }
    return [pscustomobject]@{ UseNewWindow = $useNewWindow; Reason = $reason; OrphanHelpers = $orphanHelpers }
}

function Launch-RemoteEditor {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath,
        [switch]$KnownOnFolder,
        [switch]$AuthRelaunch
    )
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog ("LAUNCH begin editor={0} path={1}" -f $EditorCmd, $RemotePath)
    }

    $script:LaunchCimCallCount = 0
    Clear-CursorProcessCache
    $script:LaunchPerfSw = [System.Diagnostics.Stopwatch]::StartNew()
    $fixes = if ($script:LaunchPerfFixes) { ($script:LaunchPerfFixes -join ',') } else { 'F1,F2,F3,F5,F4' }
    Write-EditorLaunchLog "LAUNCH_PERF_BEGIN fixes=$fixes" 'DEBUG'

    $cli = Get-EditorNativeExe $EditorCmd
    if (-not $cli) {
        Write-EditorLaunchLog 'LAUNCH: editor executable not found' 'ERROR'
        return $false
    }

    $uri = Get-RemoteFolderUri -Alias $Alias -RemotePath $RemotePath

    if ($EditorCmd -eq 'cursor') {
        # Must run before Set-CursorProxySettings: it only writes the title/color template
        # when settings.json doesn't exist yet, so on a brand-new profile the proxy merge
        # below would otherwise create a proxy-only file first and permanently skip the template.
        Initialize-CursorServerProfile
        try { [void](Ensure-CursorRemoteSshQuietSettings) } catch { Write-EditorLaunchLog "CURSOR_SSH_UI_FAIL: $($_.Exception.Message)" 'WARN' }
        # Write proxy keys to disk, but NEVER soft-stop ClaudeServerCursorProfile for proxy
        # changes. Non-owners must not SET/CLEAR. Never CLEAR while profile windows are open.
        $isProxyOwner = $true
        if ($null -ne $script:CursorProxyOwner) { $isProxyOwner = [bool]$script:CursorProxyOwner }
        if (-not $isProxyOwner) {
            Write-EditorLaunchLog 'CURSOR_PROXY_SET_SKIP: reason=non_owner' 'DEBUG'
        } else {
            # Only SET when a healthy path exists (front+backend or backend). Never pin
            # settings to constant 18998/18999 when those ports are not actually usable.
            $socksForSettings = 0
            $httpForSettings = 0
            $pathHealthy = $false
            $frontSocks = 0
            $frontHttp = 0
            if ($script:CursorSocksFrontPort) { $frontSocks = [int]$script:CursorSocksFrontPort }
            if ($script:CursorHttpFrontPort) { $frontHttp = [int]$script:CursorHttpFrontPort }
            $backSocks = 0
            $backHttp = 0
            if ($script:SocksProxyPort) { $backSocks = [int]$script:SocksProxyPort }
            if ($script:HttpProxyPort) { $backHttp = [int]$script:HttpProxyPort }
            $frontUp = $false
            $backUp = $false
            if ($frontSocks -gt 0 -and $frontHttp -gt 0 -and (Get-Command Test-LocalPortOpen -ErrorAction SilentlyContinue)) {
                $frontUp = (Test-LocalPortOpen -PortNum $frontSocks) -and (Test-LocalPortOpen -PortNum $frontHttp)
            }
            if ($backSocks -gt 0 -and $backHttp -gt 0 -and (Get-Command Test-LocalPortOpen -ErrorAction SilentlyContinue)) {
                $backUp = (Test-LocalPortOpen -PortNum $backSocks) -and (Test-LocalPortOpen -PortNum $backHttp)
            } elseif ($backSocks -gt 0 -and $backHttp -gt 0) {
                $backUp = $true
            }
            if ($frontUp -and $backUp) {
                $socksForSettings = $frontSocks
                $httpForSettings = $frontHttp
                $pathHealthy = $true
            } elseif ($backUp) {
                $socksForSettings = $backSocks
                $httpForSettings = $backHttp
                $pathHealthy = $true
            }
            if ($pathHealthy) {
                try {
                    $align = Align-CursorProxyWithRunningCli -SocksPort $socksForSettings -HttpPort $httpForSettings
                    if ($align.SocksPort) { $socksForSettings = [int]$align.SocksPort }
                    if ($align.HttpPort) { $httpForSettings = [int]$align.HttpPort }
                    $httpWrite = $httpForSettings
                    if ($httpWrite -le 0 -and $script:HttpProxyPort) { $httpWrite = [int]$script:HttpProxyPort }
                    $proxyChanged = [bool](Set-CursorProxySettings -SocksPort $socksForSettings -HttpPort $httpWrite)
                    if ($proxyChanged) {
                        Write-EditorLaunchLog ("CURSOR_PROXY_SET: preserved_open_windows socks={0} http={1} (no soft-stop)" -f $socksForSettings, $httpWrite) 'INFO'
                    }
                    Write-EditorLaunchLog 'LAUNCH_PROXY mode=proxy_settings_healthy' 'DEBUG'
                } catch { Write-EditorLaunchLog "CURSOR_PROXY_SET_FAIL: $($_.Exception.Message)" 'WARN' }
            } else {
                # No healthy socks/http after Ensure - clear dead 18998; last resort = direct.
                try {
                    $cleared = $false
                    $nOpen = 0
                    try { $nOpen = @(Get-CursorProfileProcesses -ForceRefresh).Count } catch { $nOpen = 0 }
                    if ($nOpen -gt 0) {
                        Write-EditorLaunchLog ("CURSOR_PROXY_CLEAR_SKIP: reason=windows_open action=repair_sidecar_only profile_count={0}" -f $nOpen) 'WARN'
                        if (Get-Command Repair-CursorProxySettingsToSidecar -ErrorAction SilentlyContinue) {
                            try { [void](Repair-CursorProxySettingsToSidecar) } catch {}
                        }
                    } elseif (Get-Command Clear-CursorProxySettingsSidecar -ErrorAction SilentlyContinue) {
                        try { $cleared = [bool](Clear-CursorProxySettingsSidecar) } catch { $cleared = $false }
                    }
                    if (-not $cleared -and (Test-MayClearCursorProxySettings -AllowClear)) {
                        $proxyCleared = [bool](Clear-CursorProxySettings)
                        if ($proxyCleared) {
                            Write-EditorLaunchLog 'CURSOR_PROXY_CLEAR: no_windows (no soft-stop)' 'INFO'
                            $cleared = $true
                        }
                    } elseif (-not $cleared) {
                        Write-EditorLaunchLog 'CURSOR_PROXY_CLEAR_SKIP: reason=windows_open_or_non_owner action=reload_for_server_direct' 'WARN'
                    }
                    Write-EditorLaunchLog 'LAUNCH_PROXY mode=server_direct' 'INFO'
                } catch { Write-EditorLaunchLog "CURSOR_PROXY_CLEAR_FAIL: $($_.Exception.Message)" 'WARN' }
            }
        }
    }

    $swEntry = [System.Diagnostics.Stopwatch]::StartNew()
    if ($KnownOnFolder) {
        $onFolder = $true
        Write-LaunchPerfLog -Mark 'entry_on_folder' -Ms 0 -Extra 'result=True skipped=known_on_folder'
    } else {
        $onFolder = Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath
        $swEntry.Stop()
        Write-LaunchPerfLog -Mark 'entry_on_folder' -Ms $swEntry.ElapsedMilliseconds -Extra "result=$onFolder"
    }

    $swAgent = [System.Diagnostics.Stopwatch]::StartNew()
    $agentHome = if ($EditorCmd -eq 'cursor') { Test-RemoteEditorInAgentHome -RemotePath $RemotePath } else { $false }
    $swAgent.Stop()
    Write-LaunchPerfLog -Mark 'entry_agent_home' -Ms $swAgent.ElapsedMilliseconds -Extra "result=$agentHome"

    $swProfile = [System.Diagnostics.Stopwatch]::StartNew()
    $hasProfileWindow = if ($EditorCmd -eq 'cursor') { (Get-CursorMainProfileProcesses).Count -gt 0 } else { $false }
    $profileProcCount = if ($EditorCmd -eq 'cursor') { (Get-CursorProfileProcesses).Count } else { 0 }
    $swProfile.Stop()
    Write-LaunchPerfLog -Mark 'entry_profile_counts' -Ms $swProfile.ElapsedMilliseconds -Extra "profile_main=$hasProfileWindow profile_all=$profileProcCount"

    # NEVER soft-stop ClaudeServerCursorProfile for auth. main=1 was a false signal when
    # many windows share one profile (profile_count=24 but only one "main" detected) and
    # wiped every remote window. Auth keys merge in-place into state.vscdb; no kill needed.
    if ($AuthRelaunch -and $EditorCmd -eq 'cursor' -and $profileProcCount -gt 0) {
        $mainCount = @(Get-CursorMainProfileProcesses).Count
        Write-EditorLaunchLog ("LAUNCH_KILL_SKIP: reason=auth_relaunch_never_kill profile_count={0} main={1}" -f $profileProcCount, $mainCount) 'WARN'
    }

    Write-EditorLaunchLog (
        "LAUNCH_BEGIN: exe=$cli editor=$EditorCmd alias=$Alias path=$RemotePath uri=$uri " +
        "on_folder=$onFolder agent_home=$agentHome profile_main=$hasProfileWindow profile_all=$profileProcCount " +
        "elevated=$(Test-IsElevatedShell) known_on_folder=$KnownOnFolder auth_relaunch=$AuthRelaunch"
    ) 'INFO'

    # $onFolder is now a project-scoped title/URI/cmd check (it no longer globally short-circuits on a
    # standalone "Cursor Agents" window), so it is authoritative on its own: if THIS project's window is
    # open, skip relaunch even when an unrelated agents window is also present. Gating on -not $agentHome
    # here made connect relaunch a project that was already open whenever a Cursor Agents window existed.
    if ($onFolder) {
        Write-EditorLaunchLog (
            "EDITOR_DECISION: skip_launch reason=already_on_folder on_folder=$onFolder agent_home=$agentHome " +
            "profile_main=$hasProfileWindow profile_all=$profileProcCount"
        ) 'INFO'
        Write-EditorLaunchLog 'LAUNCH_SKIP: already on correct folder - keeping Cursor open' 'INFO'
        $script:LaunchPerfSw.Stop()
        Write-LaunchPerfLog -Mark 'launch_total' -Ms $script:LaunchPerfSw.ElapsedMilliseconds -Extra 'path=skip'
        return $true
    }

    if ($script:VerboseLaunch) {
        Write-EditorLaunchVerboseState -Label 'BEGIN' -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath -IncludeSnapshot
    }

    $plan = Get-CursorLaunchWindowPlan -AgentHome $agentHome -HasProfileWindow $hasProfileWindow -ProfileProcCount $profileProcCount
    $orphanHelpers = $plan.OrphanHelpers
    $useNewWindow = $plan.UseNewWindow
    $planReason = $plan.Reason
    Write-EditorLaunchLog "LAUNCH_PLAN: use_new_window=$useNewWindow reason=$planReason profile_all=$profileProcCount" 'INFO'

    if ($EditorCmd -eq 'code') {
        $swInit = [System.Diagnostics.Stopwatch]::StartNew()
        Initialize-CodeServerProfile
        $swInit.Stop()
        Write-LaunchPerfLog -Mark 'launch_init_profile' -Ms $swInit.ElapsedMilliseconds
    }

    # Never force-kill the ClaudeServerCursorProfile tree before launch.
    # Multiple remote projects share one profile -- killing the tree closes ALL Cursor windows.
    # Prefer --new-window (already set via $useNewWindow) and keep other projects open.
    # Bug 8 note: this guard intentionally keeps using the broader $useNewWindow (unlike the
    # narrower $hasProfileWindow-based $preservedOpenWindows guard further down at the
    # post-exhaustion LAUNCH_RECOVERY_SKIP check) - its purpose is only to avoid pre-emptively
    # killing the profile tree before even TRYING the launch strategies, so it's fine/safe to be
    # broad here (orphan helpers alone are reason enough not to kill before trying). Do not
    # narrow this one to match the recovery guard - they protect against different things.
    if ($EditorCmd -eq 'cursor' -and ($agentHome -or $useNewWindow) -and ($profileProcCount -gt 0)) {
        Write-EditorLaunchLog ("LAUNCH_KILL_SKIP: reason=preserve_open_windows profile_count={0} agent_home={1} use_new_window={2}" -f $profileProcCount, $agentHome, $useNewWindow) 'INFO'
        Write-LaunchPerfLog -Mark 'launch_kill_profile' -Ms 0 -Extra 'skipped=preserve_open_windows'
    }

    $swPlan = [System.Diagnostics.Stopwatch]::StartNew()
    # Warm = profile already has activity (windows or helpers). Use --remote ONLY so we do not
    # barrage Cursor's IPC with folder-uri retries that interrupt the in-flight handoff.
    $warmHandoff = ($useNewWindow -and $profileProcCount -gt 0)
    $strategies = @(Get-RemoteEditorLaunchStrategies -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath -Uri $uri -NewWindow:$useNewWindow -WarmHandoff:$warmHandoff)
    $swPlan.Stop()
    Write-LaunchPerfLog -Mark 'launch_strategies_plan' -Ms $swPlan.ElapsedMilliseconds -Extra "count=$($strategies.Count) warm=$warmHandoff"
    Write-EditorLaunchLog "LAUNCH_STRATEGIES: count=$($strategies.Count) warm=$warmHandoff names=$($strategies.Name -join ',')" 'INFO'

    $attempt = 0
    $anyStarted = $false
    $script:LastLaunchAttempts = @()
    foreach ($strategy in $strategies) {
        $attempt++
        if ($attempt -gt 1 -and $EditorCmd -eq 'cursor') {
            # Do not wipe the profile on strategy retry -- other open projects must stay alive.
            Write-EditorLaunchLog "LAUNCH_RETRY_NO_KILL: strategy=$($strategy.Name) preserving profile windows" 'DEBUG'
        }

        if ($script:VerboseLaunch) {
            Write-EditorLaunchSnapshot -Label "PRE_ATTEMPT_${attempt}_$($strategy.Name)" -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath
        }

        Write-EditorLaunchLog "LAUNCH_ATTEMPT: n=$attempt strategy=$($strategy.Name) args=$(Format-ProcessArgumentString -ArgumentList $strategy.Args)" 'INFO'

        # Bug 2 secondary signal: window-count-before-vs-after-this-attempt, captured fresh per
        # attempt (not once for the whole launch) so a later strategy's baseline isn't stale from
        # an earlier attempt's own window changes. Cursor's single-instance IPC handoff means a
        # repeat --folder-uri/--remote request against an ALREADY-RUNNING shared-profile process
        # hands the new window to that SAME pid via an in-process IPC channel - that pid's
        # Win32_Process.CommandLine is fixed at original process-creation time and never reflects
        # the newly-requested folder (see research note below Launch-RemoteEditor), so
        # CommandLine-based detection is permanently blind to this case. Title-based detection
        # (Test-RemoteEditorOnCorrectFolder, now fixed for the site-tag bug above) covers the
        # common case, but a real Win32 top-level-window-COUNT delta on the known main profile
        # pid(s) - present before this attempt started, re-checked every poll tick - is a second,
        # title-agnostic corroborating signal that a new window genuinely materialized for THIS
        # request, not just whatever text happens to be in a window's title at the instant we
        # look. Scoped to the handoff scenario only ($useNewWindow -and $profileProcCount -gt 0)
        # so cold-start launches (own fresh process, title/URI detection already reliable) are
        # unaffected.
        $preAttemptWindowCounts = @{}
        if ($EditorCmd -eq 'cursor') {
            foreach ($p in @(Get-CursorMainProfileProcesses)) {
                $preAttemptWindowCounts[$p.ProcessId] = @(Get-ProcessTopLevelWindows -ProcessId $p.ProcessId).Count
            }
        }

        $swStart = [System.Diagnostics.Stopwatch]::StartNew()
        if (-not (Start-ProcessAsInteractiveUser -FilePath $cli -ArgumentList $strategy.Args)) {
            Write-EditorLaunchLog "LAUNCH_FAIL_START: strategy=$($strategy.Name) Start-ProcessAsInteractiveUser returned false" 'ERROR'
            continue
        }
        $swStart.Stop()
        Write-LaunchPerfLog -Mark 'start_process' -Ms $swStart.ElapsedMilliseconds -Extra "strategy=$($strategy.Name)"
        $anyStarted = $true

        $afterFolder = $false
        $afterAgent = $true
        # Poll every 250ms instead of sleeping a full 1s between checks (same 3s total
        # ceiling as before, @(1,2,3)) - a ready window is typically detected within one
        # tick of becoming ready instead of up to ~900ms late, cutting real perceived
        # launch latency without changing the worst-case per-strategy timeout.
        $pollMs = 250
        # H11_multi_window_enum: the first strategy always gets the full budget - it is the
        # one most likely to succeed and the one the window-enum fix above targets directly.
        # Strategies 2-4 are just different CLI arg spellings (--classic/--folder-uri vs
        # --remote) aimed at the SAME already-running shared-profile process via the SAME
        # single-instance IPC channel (preserve_open_windows scenario: profileProcCount>0
        # and useNewWindow). If the now-fixed detection still finds nothing for strategy 1
        # within a shorter window, it is very unlikely a differently-spelled retry against
        # that identical busy target succeeds ~2s later where the previous one did not -
        # shortening only these retries cuts real wasted time (measured ~8s/strategy x 3
        # retries) without touching the important first attempt or genuine cold-start
        # launches (no existing profile window), which still get the full 12-tick budget.
        # Warm handoff: Cursor often navigates the EXISTING profile window to the new folder
        # (title changes, window-count does NOT increase - live 2026-07-25 dakhl). Remote-SSH
        # title update routinely takes 8-15s. The old 5s ceiling (20 ticks) exhausted before
        # on_folder became true, then cascaded into folder-uri retries that interrupted IPC and
        # reported LAUNCH_FAIL even though a single later --remote would open the project.
        # Warm attempt 1 now waits up to 20s (80 ticks); success still returns on the first tick
        # that sees on_folder / window-count, so the happy path pays nothing extra.
        $pollMaxTicks =
            if ($attempt -gt 1 -and $useNewWindow -and $profileProcCount -gt 0) { 6 }
            elseif ($attempt -eq 1 -and $useNewWindow -and $profileProcCount -gt 0) { 80 }
            else { 12 }
        for ($pollTick = 1; $pollTick -le $pollMaxTicks; $pollTick++) {
            Start-Sleep -Milliseconds $pollMs
            Clear-CursorProcessCache
            $afterFolder = Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath
            $afterAgent = if ($EditorCmd -eq 'cursor') { Test-RemoteEditorInAgentHome -RemotePath $RemotePath } else { $false }

            # Bug 2 secondary signal (see comment above the baseline capture): a real window-count
            # increase on a known main profile pid during the IPC-handoff scenario, independent of
            # title text. Corroborating only - always ORed with the handoff scenario gate itself,
            # never trusted alone outside preserve-open-windows/new-window territory.
            $windowCountIncreased = $false
            if ($EditorCmd -eq 'cursor' -and $useNewWindow -and $profileProcCount -gt 0) {
                foreach ($p in @(Get-CursorMainProfileProcesses)) {
                    $curWinCount = @(Get-ProcessTopLevelWindows -ProcessId $p.ProcessId).Count
                    $baseWinCount = 0
                    if ($preAttemptWindowCounts.ContainsKey($p.ProcessId)) { $baseWinCount = $preAttemptWindowCounts[$p.ProcessId] }
                    if ($curWinCount -gt $baseWinCount) { $windowCountIncreased = $true; break }
                }
            }
            $elapsedMs = $pollTick * $pollMs
            Write-EditorLaunchLog (
                "LAUNCH_POLL: strategy=$($strategy.Name) elapsed=${elapsedMs}ms on_folder=$afterFolder agent_home=$afterAgent window_count_increased=$windowCountIncreased"
            ) 'DEBUG'
            Write-LaunchPerfLog -Mark "poll_${elapsedMs}ms" -Ms $elapsedMs -Extra "on_folder=$afterFolder strategy=$($strategy.Name)"

            # Success model (2026-07-25, "opening matters, not the title"):
            #   1) $afterFolder  -> the target project window is detected (title/URI/cmd for THIS
            #      project). This is authoritative and is NOT vetoed by the global agent_home flag: a
            #      standalone "Cursor Agents" window coexisting with the project window is normal in
            #      Cursor 3.x and must not turn a real success into a failure.
            #   2) $windowCountIncreased -> a brand-new top-level window materialized for our launch
            #      (the reliable --remote-handoff signal). Only this fallback stays gated by
            #      -not $afterAgent, to guard the rare folder-uri case where a NEW window lands on the
            #      agents splash instead of the folder.
            $launchOk = $false
            $okReason = ''
            if ($afterFolder) { $launchOk = $true; $okReason = 'on_folder' }
            elseif ($windowCountIncreased -and -not $afterAgent) { $launchOk = $true; $okReason = 'window_count_increased_no_title_match' }
            if ($launchOk) {
                Write-EditorLaunchLog "LAUNCH_OK: strategy=$($strategy.Name) attempt=$attempt reason=$okReason agent_home=$afterAgent" 'INFO'
                $script:LastLaunchAttempts += "${attempt}:$($strategy.Name):folder=$afterFolder:agent=$afterAgent:wincount=$windowCountIncreased"
                $script:LaunchPerfSw.Stop()
                Write-LaunchPerfLog -Mark 'launch_total' -Ms $script:LaunchPerfSw.ElapsedMilliseconds -Extra "path=ok strategy=$($strategy.Name)"
                return $true
            }

            if ($script:VerboseLaunch -and $pollTick -eq $pollMaxTicks) {
                Write-EditorLaunchVerboseState -Label "POLL_${elapsedMs}ms_$($strategy.Name)" -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath -IncludeSnapshot
            }
        }

        Write-EditorLaunchLog (
            "LAUNCH_ATTEMPT_RESULT: n=$attempt strategy=$($strategy.Name) on_folder=$afterFolder agent_home=$afterAgent " +
            "window_count_increased=$windowCountIncreased $(Get-RemoteEditorLaunchDiag -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)"
        ) 'INFO'
        $script:LastLaunchAttempts += "${attempt}:$($strategy.Name):folder=$afterFolder:agent=$afterAgent:wincount=$windowCountIncreased"
        if ($script:VerboseLaunch) {
            Write-EditorLaunchVerboseState -Label "RESULT_$($strategy.Name)" -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath -IncludeSnapshot
        }

        Write-EditorLaunchLog "LAUNCH_RETRY: strategy=$($strategy.Name) did not reach target folder - next strategy" 'WARN'
    }

    # Warm grace: the --remote IPC handoff may still be settling (same-window title update).
    # One more short poll for on_folder before declaring failure - covers the case where the
    # primary poll ceiling just barely missed the title flip.
    if ($anyStarted -and $warmHandoff) {
        Write-EditorLaunchLog 'LAUNCH_GRACE: warm handoff - waiting up to 10s more for on_folder' 'INFO'
        for ($g = 1; $g -le 40; $g++) {
            Start-Sleep -Milliseconds 250
            Clear-CursorProcessCache
            if (Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath) {
                Write-EditorLaunchLog ("LAUNCH_OK: strategy=grace attempt=post reason=on_folder elapsed={0}ms" -f ($g * 250)) 'INFO'
                $script:LastLaunchAttempts += "grace:on_folder"
                $script:LaunchPerfSw.Stop()
                Write-LaunchPerfLog -Mark 'launch_total' -Ms $script:LaunchPerfSw.ElapsedMilliseconds -Extra 'path=ok strategy=grace'
                return $true
            }
        }
    }

    Write-EditorLaunchVerboseState -Label 'EXHAUSTED' -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath -IncludeSnapshot -ForceLog
    $script:LaunchPerfSw.Stop()
    if (-not $anyStarted) {
        Write-EditorLaunchLog 'LAUNCH_FAIL: all strategies failed to start process' 'ERROR'
        Write-LaunchPerfLog -Mark 'launch_total' -Ms $script:LaunchPerfSw.ElapsedMilliseconds -Extra 'path=fail'
        return $false
    }

    Clear-CursorProcessCache
    $profileProcs = @(Get-EditorProfileProcessesForLaunch -EditorCmd $EditorCmd -ForceRefresh)
    if ($profileProcs.Count -eq 0) {
        Write-EditorLaunchLog 'LAUNCH_FAIL: started_but_no_process' 'ERROR'
        Write-LaunchPerfLog -Mark 'launch_total' -Ms $script:LaunchPerfSw.ElapsedMilliseconds -Extra 'path=fail_no_process'
        return $false
    }

    $mainCount = if ($EditorCmd -eq 'cursor') {
        @(Get-CursorMainProfileProcesses).Count
    } else {
        @($profileProcs | Where-Object { $_.CommandLine -and ($_.CommandLine -notmatch '--type=') }).Count
    }
    $windowOpen = Test-RemoteEditorWindowOpen -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath

    Write-EditorLaunchLog 'LAUNCH_WARN: process started but folder workspace not detected - press O to retry' 'WARN'
    if ($mainCount -eq 0) {
        Write-EditorLaunchLog 'LAUNCH_FAIL: started_but_no_process main_count=0' 'ERROR'
        Write-LaunchPerfLog -Mark 'launch_total' -Ms $script:LaunchPerfSw.ElapsedMilliseconds -Extra 'path=fail_no_main'
        return $false
    }
    if (-not $windowOpen) {
        Write-EditorLaunchLog 'LAUNCH_FAIL: started_but_wrong_or_no_folder_window' 'ERROR'
    } else {
        Write-EditorLaunchLog 'LAUNCH_FAIL: started_but_not_on_folder' 'ERROR'
    }

    # H2/H3 CONFIRMED (debug session c46ba1, live repro 2026-07-24): when another project's
    # window is already open on this shared profile, Cursor's --new-window IPC handoff to the
    # existing instance never produces a detectable second window (CommandLine-based on_folder
    # check keeps inspecting the SAME pre-existing pid, whose original CommandLine points at the
    # OTHER project and never changes) - all 4 strategies exhaust their poll budget (~56s) and
    # this recovery block used to Stop-CursorServerProfileTree, force-closing that OTHER
    # project's fully-working window (main + gpu/utility/renderer helpers) just to cold-launch
    # this one. Must mirror the same preserve_open_windows guard used before the attempts
    # (LAUNCH_KILL_SKIP above) - never destroy someone else's open Cursor session as a "recovery".
    #
    # Bug 8 fix: deliberately narrower than the earlier LAUNCH_KILL_SKIP guard at ~line 2070
    # (which uses the broader $useNewWindow). $useNewWindow is unconditionally true whenever
    # $profileProcCount -gt 0 - either directly via $hasProfileWindow, OR via $orphanHelpers
    # (Get-CursorLaunchWindowPlan) when $hasProfileWindow is FALSE but stale/invisible helper
    # processes exist. Reusing $useNewWindow here made $preservedOpenWindows always mirror the
    # very next `if`'s own "$profileProcCount -gt 0" guard, so LAUNCH_RECOVERY_SKIP fired every
    # time and the soft_stop_profile/cold_launch recovery block below was provably unreachable
    # (proven by test-launch-recovery-reachable-live.ps1 across all 12 (agentHome,
    # hasProfileWindow, profileProcCount) combinations). What this guard is ACTUALLY meant to
    # protect is a real, visible open window (or agent-home) - not the mere existence of orphan
    # helper processes with no window at all.
    #
    # Bug 14 fix (2026-07-24, live repro): $hasProfileWindow is captured ONCE at function ENTRY
    # (~line 2048), before this call's own up-to-4 launch attempts and up to ~40s of retries even
    # begin. By the time this post-exhaustion decision runs, it can be stale by tens of seconds -
    # confirmed live: a genuinely open, unrelated project's window (real main pid, alive the whole
    # time) was NOT protected because entry-time $hasProfileWindow no longer reflected current
    # reality, so Stop-CursorServerProfileTree killed that real window's whole process tree just to
    # cold-launch this one. $mainCount (line 2254) is a FRESH re-query of the exact same signal,
    # taken moments before this exact decision - use that instead of the stale entry-time value.
    # Do NOT swap this back to $useNewWindow (re-collapses the Bug 8 guard) or to $hasProfileWindow
    # (re-introduces Bug 14's stale-read window-kill).
    $preservedOpenWindows = ($EditorCmd -eq 'cursor' -and ($agentHome -or ($mainCount -gt 0)) -and ($profileProcCount -gt 0))
    if ($EditorCmd -eq 'cursor' -and $profileProcCount -gt 0 -and $preservedOpenWindows) {
        Write-EditorLaunchLog ("LAUNCH_RECOVERY_SKIP: reason=preserve_open_windows profile_count={0} - not killing other open project windows; press O to retry" -f $profileProcCount) 'WARN'
        Write-LaunchPerfLog -Mark 'launch_total' -Ms $script:LaunchPerfSw.ElapsedMilliseconds -Extra 'path=fail_preserved_open_windows'
        return $false
    }
    if ($EditorCmd -eq 'cursor' -and $profileProcCount -gt 0) {
        Write-EditorLaunchLog ("LAUNCH_RECOVERY: soft_stop_profile then cold_launch path={0}" -f $RemotePath) 'WARN'
        try { Stop-CursorServerProfileTree } catch {
            Write-EditorLaunchLog ("LAUNCH_RECOVERY_KILL_FAIL: {0}" -f $_.Exception.Message) 'WARN'
        }
        Start-Sleep -Milliseconds 400
        Clear-CursorProcessCache
        $cold = @(Get-RemoteEditorLaunchStrategies -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath -Uri $uri -NewWindow:$false)
        if ($cold.Count -gt 0) {
            $strat = $cold[0]
            Write-EditorLaunchLog ("LAUNCH_RECOVERY_ATTEMPT: strategy={0}" -f $strat.Name) 'INFO'
            if (Start-ProcessAsInteractiveUser -FilePath $cli -ArgumentList $strat.Args) {
                # A cold Cursor.exe start after soft_stop_profile has to spin up its whole
                # process tree (crashpad, gpu, utility, renderer) from disk with no warm
                # profile process to reuse - on a loaded machine (many unrelated Cursor.exe
                # processes competing for CPU/IO) this routinely takes well over the old
                # 10s budget (20*500ms). Give it a much more realistic ceiling (45s) so a
                # launch that is genuinely succeeding isn't reported as failed while the
                # window is still on its way up (confirmed live: window appeared correctly
                # ~30-60s after this loop used to give up).
                for ($tick = 1; $tick -le 90; $tick++) {
                    Start-Sleep -Milliseconds 500
                    Clear-CursorProcessCache
                    if ((Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath) -and
                        -not (Test-RemoteEditorInAgentHome -RemotePath $RemotePath)) {
                        Write-EditorLaunchLog ("LAUNCH_OK: recovery_cold_start elapsed_ms={0}" -f ($tick * 500)) 'INFO'
                        Write-LaunchPerfLog -Mark 'launch_total' -Ms $script:LaunchPerfSw.ElapsedMilliseconds -Extra 'path=ok_recovery'
                        return $true
                    }
                }
            }
        }
        Write-EditorLaunchLog 'LAUNCH_RECOVERY_FAIL: cold_start_did_not_reach_folder' 'ERROR'
    }

    Write-LaunchPerfLog -Mark 'launch_total' -Ms $script:LaunchPerfSw.ElapsedMilliseconds -Extra 'path=fail_not_on_folder'
    return $false
}

