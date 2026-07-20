from pathlib import Path
p = Path(r"D:\Smart\Claude-Code-Server\scripts\tmp\deep_ultra.py")
au = p.read_text(encoding="utf-8")
old = '''    # hang guard: mountpoint -q must not appear as active check
    if "mountpoint -q" in txt or "mountpoint -q" in txt.replace(" ", ""):
        FAIL(f"{path} uses mountpoint -q (hang risk)")
    else:
        OK(f"{os.path.basename(path)} no mountpoint -q")
'''
new = '''    # hang guard: active (non-comment) mountpoint -q is a hang risk on frozen SSHFS
    bad = []
    for i, line in enumerate(txt.splitlines(), 1):
        s = line.lstrip()
        if s.startswith("#"):
            continue
        if "mountpoint -q" in line:
            bad.append(i)
    if bad:
        FAIL(f"{path} uses mountpoint -q at lines {bad[:8]} (hang risk)")
    else:
        OK(f"{os.path.basename(path)} no active mountpoint -q")
'''
if "non-comment" in au:
    print("SKIP audit")
elif old not in au:
    raise SystemExit("old block missing")
else:
    p.write_text(au.replace(old, new), encoding="utf-8", newline="\n")
    print("OK audit")
