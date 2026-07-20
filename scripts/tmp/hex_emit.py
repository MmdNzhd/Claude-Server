from pathlib import Path
for label, p in [
    ('repo', Path('scripts/server/claude-mount.sh')),
    ('old', Path(r'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows\server\claude-mount.sh')),
]:
    if not p.exists():
        print(label, 'missing'); continue
    raw = p.read_bytes()
    # find all occurrences of emit_git
    idx = 0
    n = 0
    while True:
        i = raw.find(b'_emit_git_hide_warn', idx)
        if i < 0: break
        chunk = raw[i:i+25]
        print(label, n, chunk, list(chunk))
        idx = i + 1
        n += 1
    print(label, 'count', n, 'sha', __import__('hashlib').sha256(raw).hexdigest()[:16])
