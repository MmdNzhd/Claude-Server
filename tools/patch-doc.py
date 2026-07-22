from pathlib import Path
p = Path("docs/client-connect.md")
t = p.read_text(encoding="utf-8")
if "Windows EXE-only users" in t:
    print("docs already")
    raise SystemExit(0)
block = """

## Windows EXE-only users

Give end users **only** `Claude-Connect.exe` (on Desktop after publish). Do not hand out `claude-publish/.../windows` folders.

- First run installs into `Desktop/Claude-Connect/` and launches connect.
- Later updates download that same EXE from the server bundle (not a full script tree).
- Server install must never CRLF-strip `*.exe` (`install-client-bundle.sh`). A stripped EXE fails with "not a valid application for this OS platform".

"""
if "Questions: contact admin" in t:
    t = t.replace("Questions: contact admin", block.strip() + "\n\nQuestions: contact admin", 1)
else:
    t += block
p.write_text(t, encoding="utf-8", newline="\n")
print("docs updated")
