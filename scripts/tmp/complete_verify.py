from pathlib import Path
root = Path(r"D:\Smart\Claude-Code-Server")
fails = []
oks = []

def OK(m): oks.append(m); print("OK ", m)
def FAIL(m): fails.append(m); print("FAIL", m)

# Repo wiring
checks = [
    ("server/claude-self-heal.sh exists", (root/"scripts/server/claude-self-heal.sh").is_file()),
    ("heal has stale /proc detect", "Never use mountpoint" in (root/"scripts/server/claude-self-heal.sh").read_text(encoding="utf-8")),
    ("heal has CRLF-all", "_heal_bin_crlf_all" in (root/"scripts/server/claude-self-heal.sh").read_text(encoding="utf-8")),
    ("heal has git-off", "git.enabled" in (root/"scripts/server/claude-self-heal.sh").read_text(encoding="utf-8")),
    ("automount calls heal", "claude-self-heal" in (root/"scripts/server/claude-automount.sh").read_text(encoding="utf-8")),
    ("automount heal on tunnel-down", "tunnel down" in (root/"scripts/server/claude-automount.sh").read_text(encoding="utf-8").lower() or "Still self-heal" in (root/"scripts/server/claude-automount.sh").read_text(encoding="utf-8")),
    ("setup installs heal", "GOLDEN_HEAL" in (root/"scripts/server/laptop-exec-setup.sh").read_text(encoding="utf-8") and "claude-self-heal" in (root/"scripts/server/laptop-exec-setup.sh").read_text(encoding="utf-8")),
    ("deploy-laptop-exec all uids", "$3 >= 1000" in (root/"scripts/server/commands/deploy-laptop-exec.sh").read_text(encoding="utf-8")),
    ("deploy-laptop-exec installs heal", "claude-self-heal" in (root/"scripts/server/commands/deploy-laptop-exec.sh").read_text(encoding="utf-8")),
    ("deploy-mount-fix heal", "claude-self-heal" in (root/"scripts/server/commands/deploy-mount-fix.sh").read_text(encoding="utf-8")),
    ("add-user heal", "claude-self-heal" in (root/"scripts/server/commands/add-user.sh").read_text(encoding="utf-8")),
    ("Win git-mode push heal", "claude-self-heal.sh" in (root/"scripts/client/git-mode.ps1").read_text(encoding="utf-8")),
    ("Win conf push heal", "claude-self-heal --quiet" in (root/"scripts/client/git-mode.ps1").read_text(encoding="utf-8")),
    ("Mac git-mode push heal", "claude-self-heal.sh" in (root/"scripts/client/git-mode.sh").read_text(encoding="utf-8")),
    ("Mac conf push heal", "claude-self-heal --quiet" in (root/"scripts/client/git-mode.sh").read_text(encoding="utf-8")),
    ("Mac LAPTOP_OS in conf", "LAPTOP_OS=%s" in (root/"scripts/client/git-mode.sh").read_text(encoding="utf-8") or "LAPTOP_OS=" in (root/"scripts/client/git-mode.sh").read_text(encoding="utf-8")),
    ("Win LAPTOP_OS=windows", "LAPTOP_OS=windows" in (root/"scripts/client/git-mode.ps1").read_text(encoding="utf-8")),
    ("publish mac heal", 'mac\\claude-self-heal.sh' in (root/"publish/publish.ps1").read_text(encoding="utf-8")),
    ("publish win heal", 'windows\\claude-self-heal.sh' in (root/"publish/publish.ps1").read_text(encoding="utf-8")),
    ("publish mac automount", 'mac\\claude-automount.sh' in (root/"publish/publish.ps1").read_text(encoding="utf-8")),
    ("publish win automount", 'windows\\claude-automount.sh' in (root/"publish/publish.ps1").read_text(encoding="utf-8")),
    ("mount git-off policy", "Only remote User settings" in (root/"scripts/server/claude-mount.sh").read_text(encoding="utf-8")),
    ("no git shim in repo", not (root/"scripts/server/git-via-laptop-exec.sh").is_file()),
]
for name, ok in checks:
    (OK if ok else FAIL)(name)

print(f"REPO ok={len(oks)} fail={len(fails)}")
raise SystemExit(1 if fails else 0)
