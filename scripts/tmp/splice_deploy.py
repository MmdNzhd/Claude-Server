from pathlib import Path
root = Path(r"D:\Smart\Claude-Code-Server")
main = root / "publish/deploy-client-bundles.ps1"
frag = root / "scripts/tmp/Invoke-RemoteBundleInstall.fragment.ps1"
t = main.read_text(encoding="utf-8")
f = frag.read_text(encoding="utf-8")
start = t.find("function Invoke-RemoteBundleInstall")
end = t.find("if (-not (Test-CommandAvailable 'ssh'))")
if start < 0 or end < 0:
    raise SystemExit(f"markers missing {start} {end}")
main.write_text(t[:start] + f + "\n" + t[end:], encoding="utf-8", newline="\n")
print("OK spliced", end - start, "->", len(f))
