from pathlib import Path
root = Path(__file__).resolve().parents[2]
gm = root / "scripts/client/git-mode.sh"
g = gm.read_text(encoding="utf-8")

# Add helper near remote_login_on / laptop helpers
if "mac_login_realname()" not in g:
    anchor = "remote_login_on() {"
    helper = r'''mac_login_realname() {
    # Sharing UI shows Full Name; SSH uses short name (whoami).
    local rn=""
    rn="$(id -F 2>/dev/null | tr -d '\r\n' || true)"
    [ -n "$rn" ] || rn="$(dscl . -read "/Users/$(whoami)" RealName 2>/dev/null | tail -1 | sed 's/^RealName: *//;s/^ //' | tr -d '\r\n' || true)"
    printf '%s' "$rn"
}

'''
    if anchor not in g:
        raise SystemExit('anchor missing')
    g = g.replace(anchor, helper + anchor, 1)

old = '''    warn "Laptop SSH still not accepting the server key."
    warn "Mac login user is '${user}' (whoami) — NOT the server username."
    warn "Server username stays '${REMOTE_USER:-mohammad}'. Reverse SSH must allow Mac user '${user}'."
    warn "System Settings -> General -> Sharing -> Remote Login: ON, allow '${user}' (or All users)."
'''
# may not have .17 messages yet if they still on old - check both
if "Mac login user is" in g:
    old = '''    warn "Laptop SSH still not accepting the server key."
    warn "Mac login user is '${user}' (whoami) — NOT the server username."
    warn "Server username stays '${REMOTE_USER:-mohammad}'. Reverse SSH must allow Mac user '${user}'."
    warn "System Settings -> General -> Sharing -> Remote Login: ON, allow '${user}' (or All users)."
'''
    new = '''    warn "Laptop SSH still not accepting the server key."
    warn "SSH uses Mac short name '${user}' (whoami). Server user is '${REMOTE_USER:-?}' (different)."
    _rn="$(mac_login_realname 2>/dev/null || true)"
    if [ -n "${_rn}" ] && [ "${_rn}" != "${user}" ]; then
        warn "In System Settings the name may look like '${_rn}' — allow THAT row (or All users)."
    else
        warn "System Settings -> Sharing -> Remote Login: ON, allow '${user}' or All users."
    fi
'''
    if old not in g:
        raise SystemExit('old fail block missing')
    g = g.replace(old, new, 1)
else:
    # older fail block
    old2 = '''    warn "Laptop SSH still not accepting the server key."
    warn "System Settings -> General -> Sharing -> Remote Login: ON, allow '${user}'."
'''
    new2 = '''    warn "Laptop SSH still not accepting the server key."
    warn "SSH uses Mac short name '${user}' (whoami). Server user is '${REMOTE_USER:-?}'."
    _rn="$(mac_login_realname 2>/dev/null || true)"
    if [ -n "${_rn}" ] && [ "${_rn}" != "${user}" ]; then
        warn "In System Settings the name may look like '${_rn}' — allow THAT row (or All users)."
    else
        warn "System Settings -> Sharing -> Remote Login: ON, allow '${user}' or All users."
    fi
'''
    if old2 not in g:
        raise SystemExit('old2 missing')
    g = g.replace(old2, new2, 1)

gm.write_text(g, encoding="utf-8", newline="\n")

cs = root / "scripts/client/mac/connect.sh"
c = cs.read_text(encoding="utf-8")
for old, new in [
(
'''    warn "Mac Sharing must allow Mac login '${LAPTOP_USER:-$(whoami)}' (whoami) — not server user '${REMOTE_USER}'."
    warn "System Settings -> General -> Sharing -> Remote Login = ON, allow '${LAPTOP_USER:-$(whoami)}' (or All users)"''',
'''    _lu="${LAPTOP_USER:-$(whoami)}"; _rn="$(mac_login_realname 2>/dev/null || true)"
    warn "SSH needs Mac short name '${_lu}' (whoami), not server '${REMOTE_USER}'."
    if [ -n "${_rn}" ] && [ "${_rn}" != "${_lu}" ]; then
        warn "Sharing UI may show '${_rn}' — enable Remote Login and allow that user (or All users)."
    else
        warn "System Settings -> Sharing -> Remote Login = ON, allow '${_lu}' or All users."
    fi'''
),
(
'''    warn "Mac: System Settings -> General -> Sharing -> Remote Login = ON"
    warn "     Allow access for user: mohmmad  (or All users)"''',
'''    _lu="${LAPTOP_USER:-$(whoami)}"; _rn="$(mac_login_realname 2>/dev/null || true)"
    warn "SSH needs Mac short name '${_lu}' (whoami), not server '${REMOTE_USER}'."
    if [ -n "${_rn}" ] && [ "${_rn}" != "${_lu}" ]; then
        warn "Sharing UI may show '${_rn}' — allow that user (or All users)."
    else
        warn "Sharing -> Remote Login = ON, allow '${_lu}' or All users."
    fi'''
),
]:
    if old in c:
        c = c.replace(old, new, 1)
        break
else:
    # try current .17 style only first tuple
    pass

cs.write_text(c, encoding="utf-8", newline="\n")

for rel in [
    "scripts/client/mac/connect.sh",
    "scripts/client/windows/connect.ps1",
    "scripts/client/mac/connect-version.txt",
    "scripts/client/windows/connect-version.txt",
]:
    p = root / rel
    t = p.read_text(encoding="utf-8")
    for a,b in [("20260717.17","20260717.18"),("20260717.16","20260717.18"),("20260717.15","20260717.18")]:
        if a in t:
            t = t.replace(a,b)
            break
    if "20260717.18" not in t:
        raise SystemExit(rel)
    p.write_text(t, encoding="utf-8", newline="\n")
print("ok")
