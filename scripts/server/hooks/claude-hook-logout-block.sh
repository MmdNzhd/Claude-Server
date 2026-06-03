#!/bin/bash
# UserPromptSubmit hook: block /logout for regular users.
# smart and root can still logout (needed for token renewal).
if [[ "$USER" == "smart" || "$USER" == "root" ]]; then
    exit 0
fi
PROMPT=$(cat | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('prompt',''))" 2>/dev/null)
if [ "$PROMPT" = "/logout" ]; then
    echo "Logout is disabled on this server. Contact admin (smart)." >&2
    exit 2
fi
exit 0
