#!/usr/bin/env python3
"""Strip heredocs/quotes/pipeline filters before heavy-shell matching."""
import re
import sys

s = sys.stdin.read()
s = re.sub(
    r"<<-?\s*[\"']?([A-Za-z_][A-Za-z0-9_]*)[\"']?.*?(?:\n\1(?:\n|$))",
    " ",
    s,
    flags=re.S,
)
s = re.sub(r"'(?:\\.|[^'\\])*'", " ", s)
s = re.sub(r'"(?:\\.|[^"\\])*"', " ", s)
# | head -20 | tail -n 5 | wc -l  (filters, not project I/O)
s = re.sub(
    r"\|\s*(head|tail|wc)(?:\s+-[a-zA-Z0-9]+|\s+[0-9]+)*(?=\s*(?:\||$|;|&))",
    " ",
    s,
)
sys.stdout.write(s)
