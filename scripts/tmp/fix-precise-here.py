from pathlib import Path
p = Path(r'D:\Smart\Claude-Code-Server\scripts\tmp\precise-audit.ps1')
t = p.read_text(encoding='utf-8-sig')
# Replace the @" "@ matrix with a simple Write-Host list
old = '''Write-Host @"
  +--------------------------------------+---------------------------+
  | Condition                            | Action                    |
  +--------------------------------------+---------------------------+
  | profileProcCount==0                  | cold start, no kill       |
  | profile open + new project           | --new-window ONLY         |
  | agentHome==true                      | --new-window ONLY         |
  | launch strategy retry attempt>1      | NO_KILL log, no Stop-Proc |
  | Stop-...IfNeeded WITHOUT -Force      | return 0, no wipe         |
  | Stop-...IfNeeded WITH -Force         | still can wipe (manual)   |
  +--------------------------------------+---------------------------+
"@'''
new = '''Write-Host '  Condition -> Action' -ForegroundColor DarkCyan
Write-Host '  - profileProcCount=0 -> cold start, no kill'
Write-Host '  - profile open + new project -> new-window ONLY'
Write-Host '  - agentHome=true -> new-window ONLY'
Write-Host '  - strategy retry attempt>1 -> NO_KILL log, no Stop-Process'
Write-Host '  - Stop-IfNeeded WITHOUT -Force -> return 0, no wipe'
Write-Host '  - Stop-IfNeeded WITH -Force -> still can wipe (manual only)' '''
if old not in t:
    raise SystemExit('matrix block not found')
p.write_text(t.replace(old, new, 1), encoding='utf-8', newline='')
print('fixed')
