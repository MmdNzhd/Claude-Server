from pathlib import Path
import re

repo = Path(r"D:\Smart\Claude-Code-Server")
old_v = "20260715.17"
new_v = "20260715.18"

files = [
    repo / "scripts/client/windows/connect-version.txt",
    repo / "scripts/client/windows/connect.ps1",
    repo / "scripts/client/mac/connect.sh",
]
for f in files:
    t = f.read_text(encoding="utf-8-sig")
    if old_v not in t:
        raise SystemExit(f"{old_v} not in {f}")
    f.write_text(t.replace(old_v, new_v), encoding="utf-8", newline="")
    print(f"bumped {f.name}")

# Update test-editor-launch-strategies.ps1 assertions
test = repo / "scripts/client/tests/test-editor-launch-strategies.ps1"
tt = test.read_text(encoding="utf-8-sig")
needle = "Assert (Get-Command Stop-CursorServerProfileTreeIfNeeded -ErrorAction SilentlyContinue) 'Stop-CursorServerProfileTreeIfNeeded defined'"
extra = """
Assert ($launchSrc -match 'LAUNCH_KILL_SKIP: reason=preserve_open_windows') 'launch skips force-kill to preserve open windows'
Assert ($launchSrc -match 'LAUNCH_RETRY_NO_KILL') 'launch retry does not force-kill profile tree'
Assert ($launchSrc -notmatch \"Stop-CursorServerProfileTreeIfNeeded -Reason 'pre_launch_agent_or_new_window' -Force\") 'pre_launch force-kill removed'
Assert ($launchSrc -notmatch 'retry_before_\\$\\(\\$strategy\\.Name\\)' ) 'retry force-kill removed'
"""
# launchSrc is defined later in the file - need to put asserts after $launchSrc =
if "preserve_open_windows" not in tt:
    marker = "Assert ($launchSrc -match 'launch_total') 'launch_total perf mark'"
    if marker not in tt:
        raise SystemExit("launch_total assert not found")
    tt = tt.replace(marker, marker + "\n" + extra.strip() + "\n", 1)
    test.write_text(tt, encoding="utf-8", newline="")
    print("updated tests")
else:
    print("tests already updated")

print("done")
