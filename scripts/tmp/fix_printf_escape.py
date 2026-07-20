from pathlib import Path
p = Path(r"D:\Smart\Claude-Code-Server\publish\deploy-client-bundles.ps1")
t = p.read_text(encoding="utf-8")
# Escape bash $(...) so PowerShell expandable here-string does not evaluate it
bad = "PW=$(printf '%s' '$pwB64' | base64 -d)"
good = "PW=`$(printf '%s' '$pwB64' | base64 -d)"
# In Python string we need the backtick before $
good = "PW=`" + "$(printf '%s' '$pwB64' | base64 -d)"
# Actually write literal backtick-dollar
good = "PW=`$(printf '%s' '$pwB64' | base64 -d)"
if bad not in t:
    # maybe already escaped
    if "`$(printf" in t or "PW=`$(printf" in t:
        print("already escaped?")
    else:
        # show nearby
        idx = t.find("PW=")
        print(repr(t[idx:idx+80]))
        raise SystemExit("pattern not found")
else:
    t = t.replace(bad, "PW=`$(printf '%s' '$pwB64' | base64 -d)")
    p.write_text(t, encoding="utf-8", newline="\n")
    print("OK escaped printf subexpression")
