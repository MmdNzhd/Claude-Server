# editor-launch.ps1 — shared VS Code/Cursor launch from elevated connect.bat
# Dot-sourced by windows/connect.ps1 and users/*/connect.ps1
# Requires parent scope: $isAdmin; optional: $script:LaptopUser

function Get-EditorProcessNames {
    param([string]$EditorCmd)
    if ($EditorCmd -eq 'cursor') { return @('Cursor', 'cursor') }
    return @('Code')
}

function Test-EditorJustStarted {
    param([string[]]$Names, [datetime]$Since)
    foreach ($n in $Names) {
        $procs = Get-Process -Name $n -ErrorAction SilentlyContinue
        if (-not $procs) { continue }
        foreach ($p in $procs) {
            try {
                if ($p.StartTime -ge $Since) { return $true }
            } catch {
                return $true
            }
        }
    }
    return $false
}

function Resolve-EditorExe {
    param([string]$EditorCmd)
    $leaf = if ($EditorCmd -eq 'cursor') { 'cursor.exe' } else { 'Code.exe' }
    $folder = if ($EditorCmd -eq 'cursor') { 'cursor' } else { 'Microsoft VS Code' }

    $roots = @()
    foreach ($u in @($script:LaptopUser, $env:USERNAME) | Where-Object { $_ }) {
        $roots += Join-Path (Join-Path "C:\Users\$_" 'AppData\Local\Programs') $folder
    }
    if ($env:LOCALAPPDATA) {
        $local = Join-Path (Join-Path $env:LOCALAPPDATA 'Programs') $folder
        if ($local -notin $roots) { $roots += $local }
    }
    if ($EditorCmd -ne 'cursor') {
        $roots += Join-Path ${env:ProgramFiles} 'Microsoft VS Code'
        $pf86 = Join-Path ${env:ProgramFiles(x86)} 'Microsoft VS Code'
        if ($pf86 -notin $roots) { $roots += $pf86 }
    }

    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        foreach ($rel in @((Join-Path '_' $leaf), $leaf)) {
            $candidate = Join-Path $root $rel
            if (Test-Path $candidate) { return $candidate }
        }
    }

    $cmd = Get-Command $EditorCmd -ErrorAction SilentlyContinue
    if (-not $cmd) { return $null }
    $dir = Split-Path $cmd.Source -Parent
    for ($i = 0; $i -lt 6; $i++) {
        foreach ($rel in @((Join-Path '_' $leaf), $leaf)) {
            $candidate = Join-Path $dir $rel
            if (Test-Path $candidate) { return $candidate }
        }
        $parent = Split-Path $dir -Parent
        if ($parent -eq $dir) { break }
        $dir = $parent
    }
    if ($cmd.Source -match '\.(cmd|bat)$') { return $null }
    return $cmd.Source
}

function Get-EditorSandboxFlags {
    # MS docs: --disable-chromium-sandbox (v1.80+). Electron 39 admin: --disable-gpu-sandbox (#283526).
    return @('--disable-chromium-sandbox', '--disable-gpu-sandbox')
}

function Invoke-RemoteEditor {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$FolderUri
    )
    $exe = Resolve-EditorExe $EditorCmd
    if (-not $exe) { return -1 }

    $uriArgs = @('--folder-uri', $FolderUri)
    $since = Get-Date

    if ($isAdmin) {
        $procNames = Get-EditorProcessNames $EditorCmd
        $flags = Get-EditorSandboxFlags
        $flagText = ($flags -join ' ')
        $argText = "$flagText --folder-uri `"$FolderUri`""
        $runasLine = "`"$exe`" $argText"
        Start-Process -FilePath 'cmd.exe' `
            -ArgumentList @('/c', 'runas', '/trustlevel:0x20000', $runasLine) `
            -WindowStyle Hidden | Out-Null
        Start-Sleep -Milliseconds 3000
        if (Test-EditorJustStarted $procNames $since) { return 0 }

        & $exe @($flags + $uriArgs)
        return $LASTEXITCODE
    }

    if ($exe -match '\.exe$') { & $exe @uriArgs }
    else { & $EditorCmd @uriArgs }
    return $LASTEXITCODE
}
