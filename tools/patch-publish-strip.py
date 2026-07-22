from pathlib import Path
p = Path('publish/publish.ps1')
t = p.read_text(encoding='utf-8')

func = r'''
function Clear-PublishedWindowsToExeOnly {
    param(
        [Parameter(Mandatory)][string]$ClientRoot,
        [string]$ExePath = ''
    )
    $win = Join-Path $ClientRoot 'windows'
    if (-not (Test-Path -LiteralPath $win)) { return }
    if (-not $ExePath -or -not (Test-Path -LiteralPath $ExePath)) {
        $ExePath = Join-Path $win 'Claude-Connect.exe'
    }
    if (-not (Test-Path -LiteralPath $ExePath)) {
        Write-Host '  warn: skip windows EXE-only strip (Claude-Connect.exe missing)' -ForegroundColor DarkYellow
        return
    }
    Get-ChildItem -LiteralPath $win -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -in @('Claude-Connect.exe', 'READ-ME.txt')) { return }
        Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
    Copy-Item -LiteralPath $ExePath -Destination (Join-Path $win 'Claude-Connect.exe') -Force
    $readme = @"
Claude Connect - do not run from this folder
===========================================
This publish folder is not for end users.

Give users:
  Desktop\Claude-Connect.exe

Live install after first run:
  Desktop\Claude-Connect\
"@
    [IO.File]::WriteAllText(
        (Join-Path $win 'READ-ME.txt'),
        ($readme -replace "`n", "`r`n"),
        [Text.UTF8Encoding]::new($false)
    )
    Write-Ok 'windows\ reduced to Claude-Connect.exe only (ZIP/deploy already used full tree)'
}

'''

if 'function Clear-PublishedWindowsToExeOnly' not in t:
    # insert after first function or near top after param - find Write-Ok function end
    idx = t.find('function Write-Ok')
    if idx < 0:
        raise SystemExit('Write-Ok not found')
    # find next function after Write-Ok
    # simpler: insert before Add-Type -AssemblyName
    marker = 'Add-Type -AssemblyName System.IO.Compression.FileSystem'
    if marker not in t:
        raise SystemExit('Add-Type marker missing')
    t = t.replace(marker, func + '\n' + marker, 1)
    print('inserted strip function')
else:
    print('strip function exists')

# After Smart deploy block, strip OutDir windows
needle = '''        & (Join-Path $PSScriptRoot 'deploy-smart-bundle.ps1') -ProjectRoot $ProjectRoot -SmartClientRoot $OutDir
        if ($LASTEXITCODE -ne 0) { Write-Err "Smart server deploy failed (use -SkipServerDeploy to skip)" }
    }
}
'''
# Need unique context - after Smart zip/deploy
repl = '''        & (Join-Path $PSScriptRoot 'deploy-smart-bundle.ps1') -ProjectRoot $ProjectRoot -SmartClientRoot $OutDir
        if ($LASTEXITCODE -ne 0) { Write-Err "Smart server deploy failed (use -SkipServerDeploy to skip)" }
    }

    # Desktop browse folder: EXE only (ZIP already captured full windows\ for archive).
    if (-not $NoExe) {
        Clear-PublishedWindowsToExeOnly -ClientRoot $OutDir -ExePath (Join-Path $OutBase 'Claude-Connect.exe')
    }
}
'''

# The structure might be:
# if (-not $NoZip) { ... deploy ... }
# }
# }
# Looking at the file again - after deploy there's `}` for NoZip, then `}` weird extra

if 'Clear-PublishedWindowsToExeOnly -ClientRoot $OutDir' in t:
    print('strip call already present')
else:
    old = '''        if ($LASTEXITCODE -ne 0) { Write-Err "Smart server deploy failed (use -SkipServerDeploy to skip)" }
    }
}


}'''
    # From the read, after Smart deploy:
    #     }
    # }
    #
    #
    # }
    # if (-not $SmartOnly) {
    
    old2 = '''        if ($LASTEXITCODE -ne 0) { Write-Err "Smart server deploy failed (use -SkipServerDeploy to skip)" }
    }
}


}

if (-not $SmartOnly) {'''
    new2 = '''        if ($LASTEXITCODE -ne 0) { Write-Err "Smart server deploy failed (use -SkipServerDeploy to skip)" }
    }

    if (-not $NoExe) {
        Clear-PublishedWindowsToExeOnly -ClientRoot $OutDir -ExePath (Join-Path $OutBase 'Claude-Connect.exe')
    }
}


}

if (-not $SmartOnly) {'''
    if old2 in t:
        t = t.replace(old2, new2, 1)
        print('inserted strip call after Smart deploy')
    else:
        # try without NoZip wrapper - strip even if NoZip
        i = t.find('Smart server deploy failed')
        print('context around deploy fail:')
        print(repr(t[i:i+250]))
        raise SystemExit('deploy block not matched')

p.write_text(t, encoding='utf-8', newline='\n')
print('publish.ps1 OK')
