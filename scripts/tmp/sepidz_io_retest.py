import os, subprocess, sys
fails=[]
oks=[]

def sh(cmd, timeout=40):
    return subprocess.run(cmd, shell=True, text=True, capture_output=True, timeout=timeout)

def probe(user, proj):
    # use home tmp to avoid /tmp sticky conflicts from root-created files
    cmd = (
        f"su - {user} -c \""
        f"printf 'deep33' > $HOME/.deep33-src.txt && "
        f"laptop-exec write -p {proj} .deep33-e2e.txt < $HOME/.deep33-src.txt && "
        f"laptop-exec read -p {proj} .deep33-e2e.txt && "
        f"rm -f $HOME/.deep33-src.txt && "
        f"laptop-exec run -p {proj} -- cmd /c del .deep33-e2e.txt"
        f"\""
    )
    r = sh(cmd)
    out = (r.stdout or "") + (r.stderr or "")
    if "deep33" in out:
        print(f"OK  {user}/{proj} IO")
        oks.append(f"{user}/{proj}")
        return True
    print(f"FAIL {user}/{proj} IO: {out[:300]}")
    fails.append(f"{user}/{proj}: {out[:200]}")
    return False

# farzadb
for p in ("frontend", "backend"):
    probe("farzadb", p)
# hosseinm
probe("hosseinm", "sepidz-web")
# hosseinb
probe("hosseinb", "frontend")

# also verify mid/tokens quickly for live users
import sqlite3
GOLD=open("/etc/cursor-auth/golden/machine-id.txt","rb").read().replace(b"\r",b"").replace(b"\n",b"").strip().strip(b"\"'")
for u in ("farzadb","hosseinm","hosseinb","nimaz"):
    home=f"/home/{u}"
    for label,p in [("profile",f"{home}/.config/Cursor/machineid"),("server",f"{home}/.cursor-server/data/machineid")]:
        raw=open(p,"rb").read().replace(b"\r",b"").replace(b"\n",b"").strip().strip(b"\"'")
        print(("OK" if raw==GOLD else "FAIL"), f"{u} {label} mid")
        if raw!=GOLD: fails.append(f"{u} {label} mid")
    db=f"{home}/.config/Cursor/User/globalStorage/state.vscdb"
    c=sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    def gv(k):
        r=c.execute("select value from ItemTable where key=?",(k,)).fetchone()
        return "" if not r or r[0] is None else str(r[0])
    at,rt=gv("cursorAuth/accessToken"),gv("cursorAuth/refreshToken")
    c.close()
    print(("OK" if len(at)>20 and len(rt)>20 else "FAIL"), f"{u} tokens at={len(at)} rt={len(rt)}")
    if len(at)<=20: fails.append(f"{u} tokens")
    le=f"{home}/.local/bin/laptop-exec"
    cr=open(le,"rb").read().count(b"\r") if os.path.isfile(le) else -1
    print(("OK" if cr==0 else "FAIL"), f"{u} laptop-exec CR={cr}")
    if cr!=0: fails.append(f"{u} crlf")

print(f"SUMMARY ok={len(oks)} fail={len(fails)}")
for f in fails: print(" FAIL:", f)
sys.exit(1 if fails else 0)
