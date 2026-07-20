from pathlib import Path
path = Path(r"D:\Smart\Claude-Code-Server\scripts\server\commands\deploy-laptop-exec.sh")
text = path.read_text(encoding="utf-8")
old = '''USERS="smart amir amirhossein aria danial hamed hamed.kh kiana mahdie mehrdad mohammad parsa reza tarane designer"
echo -e "${BOLD}Deploy to users${NC}"
for u in $USERS; do
  h=$(getent passwd "$u" 2>/dev/null | cut -d: -f6)
  [ -n "$h" ] && [ -d "$h" ] || continue
'''
new = '''# All interactive human accounts (Smart + Sepidz + future users). Hardcoded lists miss Sepidz.
echo -e "${BOLD}Deploy to users${NC}"
getent passwd | awk -F: '$3 >= 1000 && $1 != "nobody" && $1 != "nfsnobody" { print $1 ":" $6 }' | while IFS=: read -r u h; do
  [ -n "$u" ] && [ -n "$h" ] && [ -d "$h" ] || continue
'''
if old not in text:
    raise SystemExit('USERS block not found')
path.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')
print('deploy-laptop-exec users loop patched')
