from pathlib import Path
import shutil
p = Path.home() / '.local/bin/claude-mount'
# This runs on laptop - wrong. We'll scp instead.
print('use server path via arg')
