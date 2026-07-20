from pathlib import Path
checks = [
 (r"scripts\client\git-mode.ps1", "claude-self-heal --quiet"),
 (r"scripts\client\git-mode.sh", "claude-self-heal --quiet"),
 (r"scripts\client\git-mode.ps1", "windows\\claude-self-heal" if False else "claude-self-heal.sh"),
 (r"scripts\client\git-mode.sh", "LAPTOP_OS="),
 (r"publish\publish.ps1", "windows\\claude-self-heal.sh"),
 (r"publish\publish.ps1", "mac\\claude-self-heal.sh"),
 (r"scripts\server\claude-self-heal.sh", "_heal_bin_crlf_all"),
 (r"scripts\server\claude-automount.sh", "claude-self-heal"),
]
root = Path(r"D:\Smart\Claude-Code-Server")
for rel, needle in checks:
    t = (root/rel).read_text(encoding="utf-8", errors="ignore")
    ok = needle in t
    print(("OK" if ok else "FAIL"), rel, "=>", needle)
print("DONE")
