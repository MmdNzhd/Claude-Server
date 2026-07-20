from pathlib import Path
root = Path('.')
print('ver', (root/'scripts/client/mac/connect-version.txt').read_text().strip())
sh = (root/'scripts/client/mac/connect.sh').read_text()
import re
print('CONNECT', re.search(r"CONNECT_VERSION='([^']+)'", sh).group(1))
t = (root/'scripts/client/mac/connect-update.sh').read_text()
print('has Client: local', 'Client: local=v%s' in t or "Client: local=v%s" in t)
print('has prefer mac', 'Prefer the layout' in t)
# show version check area
idx = t.find('local_ver=')
print(t[idx:idx+500])
