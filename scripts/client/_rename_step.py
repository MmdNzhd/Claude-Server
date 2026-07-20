from pathlib import Path
p = Path(__file__).resolve().parents[2] / "scripts/client/mac/connect.sh"
t = p.read_text(encoding="utf-8")
old = 'step "Laptop SSH backdoor"'
new = 'step "Laptop SSH access"'
if old not in t:
    if new in t:
        print("already")
    else:
        raise SystemExit("missing")
else:
    p.write_text(t.replace(old, new, 1), encoding="utf-8", newline="\n")
    print("renamed")
