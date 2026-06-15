#!/usr/bin/env python3
# check-tokens.py - per-user Claude token usage and cost estimate
# Usage: sudo python3 check-tokens.py

import json, os, sys, pwd

PRICING = {
    "claude-opus-4-8":           {"input": 5.00, "output": 25.00, "cache_read": 0.50, "cache_write": 6.25},
    "claude-opus-4-7":           {"input": 5.00, "output": 25.00, "cache_read": 0.50, "cache_write": 6.25},
    "claude-opus-4-6":           {"input": 5.00, "output": 25.00, "cache_read": 0.50, "cache_write": 6.25},
    "claude-sonnet-4-6":         {"input": 3.00, "output": 15.00, "cache_read": 0.30, "cache_write": 3.75},
    "claude-haiku-4-5":          {"input": 1.00, "output":  5.00, "cache_read": 0.10, "cache_write": 1.25},
    "claude-haiku-4-5-20251001": {"input": 1.00, "output":  5.00, "cache_read": 0.10, "cache_write": 1.25},
}

def get_price(model):
    for key, p in PRICING.items():
        if model.startswith(key) or key.startswith(model):
            return p
    return PRICING["claude-sonnet-4-6"]

def calc_cost(usage):
    total = 0.0
    M = 1_000_000
    for model, s in usage.items():
        p = get_price(model)
        total += (s.get("inputTokens",              0) / M) * p["input"]
        total += (s.get("outputTokens",             0) / M) * p["output"]
        total += (s.get("cacheReadInputTokens",     0) / M) * p["cache_read"]
        total += (s.get("cacheCreationInputTokens", 0) / M) * p["cache_write"]
    return total

def fmt(n):
    if n >= 1_000_000: return f"{n/1_000_000:.1f}M"
    if n >= 1_000:     return f"{n/1_000:.0f}K"
    return str(n)

# gather all human users
users = []
for pw in pwd.getpwall():
    if pw.pw_uid >= 1000 and os.path.isdir(pw.pw_dir):
        users.append(pw.pw_name)
users = sorted(set(users))

rows = []
for u in users:
    path = f"/home/{u}/.claude/stats-cache.json"
    if not os.path.exists(path):
        continue
    try:
        with open(path) as f:
            d = json.load(f)
        usage = d.get("modelUsage", {})
        if not usage:
            continue
        total_in  = sum(v.get("inputTokens",              0) for v in usage.values())
        total_out = sum(v.get("outputTokens",             0) for v in usage.values())
        total_cr  = sum(v.get("cacheReadInputTokens",     0) for v in usage.values())
        total_cw  = sum(v.get("cacheCreationInputTokens", 0) for v in usage.values())
        cost      = calc_cost(usage)
        msgs      = d.get("totalMessages",  0)
        sess      = d.get("totalSessions",  0)
        first     = (d.get("firstSessionDate") or "")[:10]
        models    = list(usage.keys())
        rows.append((u, total_in, total_out, total_cr, total_cw, cost, msgs, sess, first, models))
    except Exception as e:
        print(f"  [!] {u}: {e}", file=sys.stderr)

rows.sort(key=lambda r: r[5], reverse=True)

print()
print("=== Claude Token Usage & Cost Estimate ===")
print()
print(f"  {'User':<14}  {'Input':>7}  {'Output':>7}  {'Cache R':>8}  {'Cache W':>8}  {'Cost USD':>10}  {'Msgs':>7}  {'Sess':>6}  {'Since':>10}")
print("  " + "─" * 86)

total_cost = 0.0
for u, ti, to, cr, cw, cost, msgs, sess, first, models in rows:
    total_cost += cost
    print(f"  {u:<14}  {fmt(ti):>7}  {fmt(to):>7}  {fmt(cr):>8}  {fmt(cw):>8}  ${cost:>9.2f}  {msgs:>7,}  {sess:>6,}  {first:>10}")

print("  " + "─" * 86)
print(f"  {'TOTAL':<14}  {'':>7}  {'':>7}  {'':>8}  {'':>8}  ${total_cost:>9.2f}")
print()
print("  Note: cache_read ≈ 10% of input price, cache_write ≈ 125% of input price")
print("        Cost is an estimate based on public Anthropic pricing.")
print()

# per-model breakdown
print("=== Model Breakdown ===")
print()
model_totals = {}
for u, ti, to, cr, cw, cost, msgs, sess, first, models in rows:
    path = f"/home/{u}/.claude/stats-cache.json"
    try:
        with open(path) as f:
            d = json.load(f)
        for model, s in d.get("modelUsage", {}).items():
            if model not in model_totals:
                model_totals[model] = {"input": 0, "output": 0, "cr": 0, "cw": 0}
            model_totals[model]["input"]  += s.get("inputTokens",              0)
            model_totals[model]["output"] += s.get("outputTokens",             0)
            model_totals[model]["cr"]     += s.get("cacheReadInputTokens",     0)
            model_totals[model]["cw"]     += s.get("cacheCreationInputTokens", 0)
    except:
        pass

for model, s in sorted(model_totals.items()):
    p = get_price(model)
    M = 1_000_000
    c = (s["input"]/M)*p["input"] + (s["output"]/M)*p["output"] + (s["cr"]/M)*p["cache_read"] + (s["cw"]/M)*p["cache_write"]
    print(f"  {model:<35}  out={fmt(s['output']):>7}  cache_r={fmt(s['cr']):>8}  cost=${c:.2f}")

print()
