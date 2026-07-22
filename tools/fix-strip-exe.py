from pathlib import Path
p = Path("scripts/server/commands/install-client-bundle.sh")
t = p.read_text(encoding="utf-8")
a = "        *.bat) ;;  # Windows batch needs CRLF\n        *) _strip_crlf \"$f\" ;;"
b = "        *.bat) ;;  # Windows batch needs CRLF\n        *.exe|*.EXE) ;;  # binary SFX / PE - never sed CRLF\n        *) _strip_crlf \"$f\" ;;"
if "*.exe|*.EXE" not in t:
    if a not in t:
        raise SystemExit("pattern a missing")
    t = t.replace(a, b, 1)
    print("exe case ok")
else:
    print("exe case exists")
marker = "done < <(find \"$STAGE\" -type f -print0)\n"
check = marker + "\n# Fail install if Claude-Connect.exe present but not valid PE.\nif [ -f \"$STAGE/Claude-Connect.exe\" ]; then\n  if ! python3 - \"$STAGE/Claude-Connect.exe\" <<\"ENDPE\"\nimport struct, sys\nf=open(sys.argv[1], \"rb\")\nassert f.read(2)==b\"MZ\"\nf.seek(0x3C)\no=struct.unpack(\"<I\", f.read(4))[0]\nf.seek(o)\nassert f.read(4)==b\"PE\"+bytes(2)\nENDPE\n  then\n    fail \"Claude-Connect.exe is corrupt (not a valid PE) - refusing install\"\n  fi\n  ok \"Claude-Connect.exe PE header valid\"\nfi\n"
if "PE header valid" not in t:
    if marker not in t:
        raise SystemExit("marker missing")
    t = t.replace(marker, check, 1)
    print("pe check ok")
else:
    print("pe check exists")
p.write_text(t, encoding="utf-8", newline="\n")
print("done")
