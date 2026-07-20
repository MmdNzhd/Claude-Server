from pathlib import Path

# --- connect-update.sh: prefer REMOTE_USER=smart from conf; never use whoami for Smart ---
p = Path('scripts/client/mac/connect-update.sh')
# work on laptop via content we'll write back
print('will patch via laptop-exec')
