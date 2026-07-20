from pathlib import Path
def dump(path, start, end):
    lines = Path(path).read_text(encoding='utf-8', errors='replace').splitlines()
    for i in range(start-1, min(end, len(lines))):
        print(f'{i+1}|{lines[i]}')
    print('---')
dump('scripts/client/connect-ui.ps1', 100, 160)
dump('scripts/client/connect-ui.ps1', 640, 690)
dump('scripts/client/windows/connect.ps1', 630, 665)
dump('scripts/client/windows/connect.ps1', 1645, 1675)
dump('scripts/client/connect-ui.sh', 145, 170)
dump('scripts/client/connect-ui.sh', 415, 475)
dump('scripts/client/git-mode.sh', 1034, 1055)
dump('scripts/client/mac/connect.sh', 1, 30)
dump('scripts/client/mac/connect-update.sh', 140, 165)
dump('scripts/client/windows/connect-update.ps1', 1, 60)
