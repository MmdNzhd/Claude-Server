from pathlib import Path
p = Path("publish/publish.ps1")
t = p.read_text(encoding="utf-8")
old = """    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }"""
new = """    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }"""
# only inside New-ClientZipFromDirectory - first occurrence after that function
i = t.find("function New-ClientZipFromDirectory")
if i < 0: raise SystemExit("fn missing")
j = t.find(old, i)
if j < 0:
    if "Add-Type -AssemblyName System.IO.Compression\n    Add-Type -AssemblyName System.IO.Compression.FileSystem" in t[i:i+400]:
        print("already has both Add-Type")
    else:
        raise SystemExit("old block missing")
else:
    t = t[:j] + new + t[j+len(old):]
    p.write_text(t, encoding="utf-8", newline="\n")
    print("zip Add-Type fixed")
