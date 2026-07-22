from pathlib import Path
p = Path("scripts/client/tests/test-p0-connect-fixes.ps1")
t = p.read_text(encoding="utf-8")
ver = "20260720.25"
needle = "mac/connect.sh CONNECT_VERSION"
out = []
replaced = 0
for line in t.splitlines(True):
    if needle in line and "Assert" in line:
        out.append(
            f"Assert ($macConnect -match \"CONNECT_VERSION='{ver.replace('.', r'\\.')}'\") "
            f"'mac/connect.sh CONNECT_VERSION is {ver}'\n"
        )
        replaced += 1
    else:
        out.append(line)
p.write_text("".join(out), encoding="utf-8", newline="\n")
print("replaced", replaced)
for i, l in enumerate(p.read_text().splitlines(), 1):
    if "CONNECT_VERSION" in l and "Assert" in l:
        print(i, l)
