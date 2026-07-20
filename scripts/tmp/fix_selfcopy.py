from pathlib import Path
p = Path(r"D:\Smart\Claude-Code-Server\scripts\tmp\sepidz_proper_deploy.ps1")
lines = p.read_text(encoding="utf-8").splitlines()
out = []
for ln in lines:
    if "Copy-Item (Join-Path $stage 'connect-version.txt') (Join-Path $stage 'connect-version.txt')" in ln:
        print("drop:", ln)
        continue
    out.append(ln)
p.write_text("\n".join(out) + "\n", encoding="utf-8", newline="\n")
print("done")
