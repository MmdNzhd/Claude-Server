from pathlib import Path
sh = Path(r"D:\Smart\Claude-Code-Server\scripts\client\git-mode.sh").read_text(encoding="utf-8")
assert "claude-self-heal.sh" in sh
assert "claude-self-heal --quiet" in sh
i = sh.find("push_laptop_exec_bundle")
chunk = sh[i:i+2200]
print(chunk)
# ensure not truncated mid-line
assert "true' >/dev/null 2>&1 || true" in chunk or 'true" >/dev/null' in chunk
ps = Path(r"D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1").read_text(encoding="utf-8")
assert "claude-self-heal.sh" in ps
assert "claude-self-heal --quiet" in ps
print("VERIFY_OK")
