from pathlib import Path
w = Path('scripts/client/windows/connect.ps1').read_text(encoding='utf-8')
i = w.find('Reloading $EditorName (auth refresh)')
print('win idx', i)
print(w[i-500:i+800])
print('==== MAC after auth ====')
m = Path('scripts/client/mac/connect.sh').read_text(encoding='utf-8')
# find _editor_opened after auth case
i = m.find("repair_cursor_composer_workspace_bindings")
print(m[i:i+1800])
