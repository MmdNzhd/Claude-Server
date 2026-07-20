from pathlib import Path
p = Path('scripts/client/mac/connect.sh')
t = p.read_text(encoding='utf-8')

old = '''            if [ "$_editor_opened" -eq 0 ]; then
                step "Opening $EDITOR_NAME"
                if declare -F launch_remote_editor >/dev/null 2>&1; then
                    if launch_remote_editor "$EDITOR_CMD" "$ALIAS" "$go_path" "$_on_folder"; then
                        step_ok "$go_path"
                        _did_launch=1
                        _editor_seen_open=1
'''

new = '''            # Win parity: auth refresh relaunches even when already on folder.
            _auth_relaunch=0
            [ "${CURSOR_AUTH_RELAUNCH:-0}" = "1" ] && _auth_relaunch=1
            if [ "$_auth_relaunch" -eq 1 ] || [ "$_editor_opened" -eq 0 ]; then
                if [ "$_auth_relaunch" -eq 1 ] && [ "$_on_folder" -eq 1 ]; then
                    step "Reloading $EDITOR_NAME (auth refresh)"
                    if declare -F connect_log >/dev/null 2>&1; then
                        connect_log 'EDITOR_LAUNCH auth_relaunch despite already_on_folder' 'INFO'
                    fi
                elif [ "$_editor_opened" -eq 0 ]; then
                    step "Opening $EDITOR_NAME"
                else
                    step "Reloading $EDITOR_NAME (auth refresh)"
                fi
                if declare -F launch_remote_editor >/dev/null 2>&1; then
                    if launch_remote_editor "$EDITOR_CMD" "$ALIAS" "$go_path" "$_on_folder"; then
                        step_ok "$go_path"
                        _did_launch=1
                        _editor_seen_open=1
                        export CURSOR_AUTH_RELAUNCH=0
'''

if old not in t:
    raise SystemExit('MISS old block')
t = t.replace(old, new, 1)
p.write_text(t, encoding='utf-8', newline='\n')
print('PATCHED', 'Reloading $EDITOR_NAME (auth refresh)' in t)
