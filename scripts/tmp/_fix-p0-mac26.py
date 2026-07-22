from pathlib import Path
p = Path("scripts/client/tests/test-p0-connect-fixes.ps1")
t = p.read_text(encoding="utf-8")
t2 = t.replace("CONNECT_VERSION='20260720\\.25'", "CONNECT_VERSION='20260720\\.26'")
t2 = t2.replace("CONNECT_VERSION='20260720\\.25'", "CONNECT_VERSION='20260720\\.26'")  # noop if done
# also unescaped wrong form
import re
out=[]
for line in t.splitlines(True):
    if "mac/connect.sh CONNECT_VERSION" in line and "Assert" in line:
        out.append("Assert ($macConnect -match \"CONNECT_VERSION='20260720\\\\.26'\") 'mac/connect.sh CONNECT_VERSION is 20260720.26'\n")
    else:
        out.append(line)
# wait - in file we need single backslash for PS regex: CONNECT_VERSION='20260720\.26'
out=[]
for line in t.splitlines(True):
    if "mac/connect.sh CONNECT_VERSION" in line and "Assert" in line:
        out.append('Assert ($macConnect -match "CONNECT_VERSION=\'20260720\\.26\'") \'mac/connect.sh CONNECT_VERSION is 20260720.26\'\n')
    else:
        out.append(line)
p.write_text("".join(out), encoding="utf-8", newline="\n")
print([l for l in p.read_text().splitlines() if "mac/connect" in l and "Assert" in l][0])
