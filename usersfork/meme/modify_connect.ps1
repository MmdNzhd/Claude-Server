# Read the original file
$lines = Get-Content connect.ps1

# Find the insertion point (line 477 - before $alreadyDown = $false)
$newLines = @()
$inserted = $false

for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($i -eq 476 -and -not $inserted) {
        # Insert the main loop start
        $newLines += '    :mainLoop while ($true) {'
        $inserted = $true
    }
    
    $newLines += $lines[$i]
    
    # After the finally block ends (line 657), add menu logic
    if ($i -eq 656) {
        # Add menu after the finally block closes
        $newLines += ''
        $newLines += '        # After disconnecting, ask user what to do'
        $newLines += '        Write-Host "" '
        $newLines += '        Write-Host "    Disconnected. What would you like to do?" -ForegroundColor Cyan'
        $newLines += '        Write-Host "    C = connect again   X = exit" -ForegroundColor DarkGray'
        $newLines += '        Write-Host "" '
        $newLines += '        '
        $newLines += '        $choice = "" '
        $newLines += '        while ($choice -ne "c" -and $choice -ne "x") {'
        $newLines += '            if ([Console]::KeyAvailable) {'
        $newLines += '                $ki = [Console]::ReadKey($true)'
        $newLines += '                $choice = $ki.KeyChar.ToString().ToLower()'
        $newLines += '                if ($choice -eq "c") {'
        $newLines += '                    Write-Host "    Reconnecting..." -ForegroundColor Green'
        $newLines += '                    Start-Sleep -Seconds 1'
        $newLines += '                    continue mainLoop'
        $newLines += '                } elseif ($choice -eq "x") {'
        $newLines += '                    Write-Host "    Exiting..." -ForegroundColor DarkGray'
        $newLines += '                    break mainLoop'
        $newLines += '                }'
        $newLines += '            }'
        $newLines += '            Start-Sleep -Milliseconds 100'
        $newLines += '        }'
        $newLines += '    }'
    }
}

# Write to a new file
$newLines | Set-Content connect_new.ps1 -Encoding UTF8
Write-Host 'Modified file created as connect_new.ps1'
