from pathlib import Path
import hashlib, subprocess
p = Path.home() / '.local/bin/claude-mount'
# This runs ON LAPTOP via laptop-exec run - wrong. Need server.
print('this is laptop path check only')
