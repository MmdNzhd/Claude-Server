import json, os, sqlite3, subprocess

def sh(cmd):
    print("+", cmd, flush=True)
    r = subprocess.run(cmd, shell=True, text=True, capture_output=True)
    print((r.stdout or "").rstrip(), flush=True)
    if r.stderr:
        print((r.stderr or "").rstrip(), flush=True)
    return r

auth = json.load(open("/etc/cursor-auth/golden/auth.json"))
print("golden auth keys:", sorted(auth.keys()))
for k in ["accessToken","refreshToken","cachedEmail","cachedSignUpType","stripeMembershipType","stripeSubscriptionStatus"]:
    v = auth.get(k)
    print(f"  golden[{k!r}] type={type(v).__name__} empty={v in (None,'')} repr={'' if v is None else (str(v)[:40]+('...' if len(str(v))>40 else ''))!r}")

sk = {}
try:
    sk = json.load(open("/etc/cursor-auth/golden/state-keys.json"))
    print("state-keys count", len(sk))
    for k in sorted(sk):
        if "cursorAuth" in k or "Email" in k or "stripe" in k or "SignUp" in k:
            v = sk[k]
            print(f"  sk[{k}]={'' if v is None else str(v)[:60]!r}")
except Exception as e:
    print("no state-keys", e)

db = "/home/farzadb/.config/Cursor/User/globalStorage/state.vscdb"
c = sqlite3.connect(db)
print("BEFORE db values:")
for k, in c.execute("select key from ItemTable where key like 'cursorAuth/%' order by key"):
    v = c.execute("select value from ItemTable where key=?", (k,)).fetchone()[0]
    s = "" if v is None else str(v)
    print(f"  {k} empty={not s.strip()} len={len(s)} preview={s[:40]!r}")

# Prefer non-empty from golden auth.json; also pull from state-keys.json cursorAuth/*
mapping = {
  "accessToken":"cursorAuth/accessToken",
  "refreshToken":"cursorAuth/refreshToken",
  "cachedEmail":"cursorAuth/cachedEmail",
  "cachedSignUpType":"cursorAuth/cachedSignUpType",
  "stripeMembershipType":"cursorAuth/stripeMembershipType",
  "stripeSubscriptionStatus":"cursorAuth/stripeSubscriptionStatus",
}
written = []
cur = c.cursor()
for src, dst in mapping.items():
    val = auth.get(src)
    if (val is None or str(val).strip() == "") and dst in sk:
        val = sk[dst]
    if val is None or str(val).strip() == "":
        # try alternate key forms in state-keys
        for alt in (src, "cursorAuth/"+src, dst):
            if alt in sk and sk[alt] not in (None, ""):
                val = sk[alt]
                break
    if val is None or str(val).strip() == "":
        print("SKIP empty", dst)
        continue
    cur.execute("insert or replace into ItemTable(key,value) values(?,?)", (dst, str(val)))
    written.append((dst, len(str(val))))

# also merge all state-keys non-empty
for k, v in sk.items():
    if v is None or (isinstance(v, str) and not v.strip()):
        continue
    if isinstance(v, (dict, list)):
        cur.execute("insert or replace into ItemTable(key,value) values(?,?)", (k, json.dumps(v)))
    else:
        cur.execute("insert or replace into ItemTable(key,value) values(?,?)", (k, str(v)))
    written.append((k, len(str(v))))

c.commit()
print("WRITTEN", len(written))
print("AFTER:")
for k, in c.execute("select key from ItemTable where key like 'cursorAuth/%' order by key"):
    v = c.execute("select value from ItemTable where key=?", (k,)).fetchone()[0]
    s = "" if v is None else str(v)
    print(f"  {k} empty={not s.strip()} len={len(s)} preview={s[:40]!r}")
c.close()
os.chown(db, 1006, 1006)

# frontend write ACL probe from laptop via tunnel
print("=== frontend ACL ===")
sh("su - farzadb -c 'laptop-exec run -p frontend -- powershell -NoProfile -Command \"Get-Acl E:/WebApplication/SepidzWebApp/Frontend | Format-List; (Get-Item E:/WebApplication/SepidzWebApp/Frontend).Attributes\"'")
# try write via laptop-exec instead of SSHFS
sh("su - farzadb -c 'echo probe > /tmp/p.txt; laptop-exec write -p frontend .claude-e2e-probe.txt < /tmp/p.txt; laptop-exec read -p frontend .claude-e2e-probe.txt; laptop-exec run -p frontend -- powershell -NoProfile -Command \"Remove-Item -Force .claude-e2e-probe.txt -ErrorAction SilentlyContinue\"'")

print("DONE")
