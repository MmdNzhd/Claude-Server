from pathlib import Path
p = Path('scripts/client/editor-launch.ps1')
t = p.read_text(encoding='utf-8')
if 'LAUNCH_RECOVERY: soft_stop_profile' in t:
    print('recovery already present')
else:
    needle = 'LAUNCH_FAIL: started_but_no_window'
    i = t.find(needle)
    if i < 0: raise SystemExit('needle missing')
    start = t.rfind('    if (-not $windowOpen)', 0, i)
    if start < 0: raise SystemExit('start missing')
    end_marker = '    return $false\n}\n'
    end = t.find(end_marker, i)
    if end < 0: raise SystemExit('end missing')
    end = end + len(end_marker)
    repl = '    if (-not $windowOpen) {\n        Write-EditorLaunchLog \'LAUNCH_FAIL: started_but_wrong_or_no_folder_window\' \'ERROR\'\n    } else {\n        Write-EditorLaunchLog \'LAUNCH_FAIL: started_but_not_on_folder\' \'ERROR\'\n    }\n\n    if ($EditorCmd -eq \'cursor\' -and $profileProcCount -gt 0) {\n        Write-EditorLaunchLog ("LAUNCH_RECOVERY: soft_stop_profile then cold_launch path={0}" -f $RemotePath) \'WARN\'\n        try { Stop-CursorServerProfileTree } catch {\n            Write-EditorLaunchLog ("LAUNCH_RECOVERY_KILL_FAIL: {0}" -f $_.Exception.Message) \'WARN\'\n        }\n        Start-Sleep -Milliseconds 400\n        Clear-CursorProcessCache\n        $cold = @(Get-RemoteEditorLaunchStrategies -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath -Uri $uri -NewWindow:$false)\n        if ($cold.Count -gt 0) {\n            $strat = $cold[0]\n            Write-EditorLaunchLog ("LAUNCH_RECOVERY_ATTEMPT: strategy={0}" -f $strat.Name) \'INFO\'\n            if (Start-ProcessAsInteractiveUser -FilePath $cli -ArgumentList $strat.Args) {\n                for ($tick = 1; $tick -le 20; $tick++) {\n                    Start-Sleep -Milliseconds 500\n                    Clear-CursorProcessCache\n                    if ((Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath) -and\n                        -not (Test-RemoteEditorInAgentHome -RemotePath $RemotePath)) {\n                        Write-EditorLaunchLog \'LAUNCH_OK: recovery_cold_start\' \'INFO\'\n                        Write-LaunchPerfLog -Mark \'launch_total\' -Ms $script:LaunchPerfSw.ElapsedMilliseconds -Extra \'path=ok_recovery\'\n                        return $true\n                    }\n                }\n            }\n        }\n        Write-EditorLaunchLog \'LAUNCH_RECOVERY_FAIL: cold_start_did_not_reach_folder\' \'ERROR\'\n    }\n\n    Write-LaunchPerfLog -Mark \'launch_total\' -Ms $script:LaunchPerfSw.ElapsedMilliseconds -Extra \'path=fail_not_on_folder\'\n    return $false\n}\n'
    t = t[:start] + repl + t[end:]
    p.write_text(t, encoding='utf-8', newline='\n')
    print('editor-launch recovery patched')

c = Path('scripts/client/windows/connect.ps1')
ct = c.read_text(encoding='utf-8')
a = 'StepFail "$EditorName failed to start (elevated launch). Keep connect open and press O, or launch Cursor manually with ClaudeServerCursorProfile."'
b = 'StepFail "$EditorName did not open the project folder. Press O to retry (resets server Cursor profile windows if stuck), or open Cursor with ClaudeServerCursorProfile."'
if a in ct:
    c.write_text(ct.replace(a, b), encoding='utf-8', newline='\n')
    print('connect.ps1 message patched')
elif 'did not open the project folder' in ct:
    print('connect.ps1 already patched')
else:
    print('WARN connect.ps1 StepFail string not found')
