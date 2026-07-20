from pathlib import Path
m = Path('scripts/client/mac/connect.sh').read_text(encoding='utf-8')
i = m.find('repair_cursor_composer_workspace_bindings')
chunk = m[i:i+2200]
Path('scripts/tmp/mac-auth-launch-snip.txt').write_text(chunk, encoding='utf-8')
print('wrote snip len', len(chunk))
# also find Opening EDITOR
for j,l in enumerate(m.splitlines(),1):
    if 'Opening' in l and 'EDITOR' in l:
        print(j, l)
    if 'launch_remote_editor' in l and j>800 and j<950:
        print(j, l)
