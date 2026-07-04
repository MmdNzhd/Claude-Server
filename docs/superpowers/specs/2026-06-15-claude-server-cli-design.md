# claude-server CLI — Design Spec

**Date:** 2026-06-15
**Status:** Approved

---

## هدف

یه CLI ابزار واحد (`claude-server`) که نصب، مدیریت کاربران، وریفای، و وضعیت سرور Claude Code رو یه‌جا مدیریت کنه. با یه دستور روی سرور جدید نصب بشه و بعدش همه عملیات ادمین از طریق همون CLI انجام بشه.

---

## Bootstrap (نصب اولیه)

```bash
git clone <repo>
cd claude-code-server
sudo bash scripts/server/claude-server install
```

این دستور:
1. همه system dependencies رو نصب می‌کنه
2. Claude Code CLI نصب می‌کنه
3. wrapper و hooks رو deploy می‌کنه
4. designer dependencies رو نصب می‌کنه (Xvfb، x11vnc، noVNC، Chrome)
5. یوزر `designer` رو می‌سازه
6. یوزر ادمین `smart` رو می‌سازه
7. خود `claude-server` رو روی `/usr/local/bin/claude-server` نصب می‌کنه

بعد از bootstrap، از هرجایی:
```bash
claude-server <command> [options]
```

---

## ساختار فایل‌ها

```
scripts/server/
├── claude-server              ← dispatcher (نصب می‌شه روی /usr/local/bin)
├── commands/
│   ├── install.sh             ← نصب کامل سرور (جایگزین server-setup.sh + install-designer-deps.sh + setup-designer.sh)
│   ├── add-user.sh            ← ساخت یوزر developer (جایگزین setup-new-user.sh)
│   ├── verify.sh              ← تست همه components (جایگزین check-users.sh)
│   └── status.sh              ← وضعیت فعلی (sessions + usage)
├── hooks/
│   ├── claude-hook-pre.sh
│   ├── claude-hook-stop.sh    ← شامل STATS logging (توکن per-user)
│   └── claude-hook-logout-block.sh
├── claude-wrapper.sh
├── claude-limits.conf
├── check-tokens.py            ← گزارش دقیق توکن (نیاز به sudo)
└── check-usage.sh             ← گزارش prompt count از log
```

> **قانون:** هر تغییری در هر فایل این پوشه باید در `commands/install.sh` یا `commands/add-user.sh` هم منعکس بشه.

---

## Subcommands

### `claude-server install`

نصب کامل روی سرور تازه. idempotent — می‌شه دوباره زد.

**مراحل:**
1. چک root بودن
2. `apt-get update` + install deps: `sshfs curl git python3 xvfb x11vnc fluxbox autocutsel websockify novnc`
3. Node.js LTS نصب (اگر نیست)
4. Claude Code نصب: `npm install -g @anthropic-ai/claude-code`
5. `claude-real` symlink
6. wrapper → `/usr/local/bin/claude`
7. hooks → `/usr/local/bin/claude-hook-*`
8. `claude-automount`, `claude-git-setup`, `claude-mount` → `/usr/local/bin/` و `/usr/local/lib/`
9. `/etc/claude-limits.conf`
10. `/var/run/claude-active` (chmod 1777)
11. `/var/log/claude-activity.jsonl` (touch + chmod 666)
12. Chrome نصب (اگر نیست)
13. یوزر `designer` + setup
14. یوزر `smart` + sudo
15. SSH forwarding فعال
16. خود `claude-server` → `/usr/local/bin/claude-server`
17. نمایش دستور بعدی (token setup)

---

### `claude-server add-user <username>`

```bash
claude-server add-user amir
claude-server add-user parsa --no-password-change
```

**مراحل:**
1. چک root بودن
2. useradd (اگر نیست)
3. `/home/<user>/work` بسازه
4. `chmod 700 /home/<user>`
5. `~/.local/bin/claude-mount` نصب
6. `~/.local/bin/claude-git-setup` نصب
7. `~/.claude/settings.json` بنویسه (با hooks کامل)
8. `~/.ssh/authorized_keys` آماده کنه
9. auto-mount hook به `.bashrc` اضافه کنه
10. `chage -d 0` (تغییر پسورد اجباری در اولین login)

**Options:**
- `--no-password-change` — بدون اجبار تغییر پسورد

---

### `claude-server verify`

تست همه components. exit code 0 = سالم، 1 = مشکل.

**چک‌ها:**
- `claude-real --version` کار می‌کنه
- `/usr/local/bin/claude` symlink/wrapper وجود داره
- `/usr/local/bin/claude-hook-*` همه نصبن و executable
- `/etc/claude-limits.conf` وجود داره
- `/var/run/claude-active` وجود داره و writable
- `/var/log/claude-activity.jsonl` وجود داره و writable
- `designer-start status` OK
- برای هر یوزر human: hooks در settings.json، automount در .bashrc، `claude-mount` نصبه

خروجی رنگی مثل `check-users.sh` فعلی.

---

### `claude-server status`

```
=== Claude Server Status ===

Active sessions: 3
  aria.12345.active
  amir.23456.active
  smart.34567.active

=== Usage (last 7 days) ===
  User          Prompts  Sessions  Last active
  aria               13        11  2026-06-15 07:09
  ...

=== Token Usage (from stats cache) ===
  smart          3.8M out   $281.20   7,682 msgs
  hamed.kh       1.3M out   $107.68   2,893 msgs
```

---

### `claude-server --help`

```
Usage: claude-server <command> [options]

Commands:
  install              نصب کامل سرور (باید root باشی)
  add-user <name>      اضافه کردن یوزر developer جدید
  verify               تست همه components
  status               وضعیت فعلی sessions و usage

Options:
  --help               این راهنما
  --version            نسخه

Examples:
  sudo claude-server install
  sudo claude-server add-user amir
  claude-server verify
  claude-server status
```

---

## مدیریت docs

فایل‌های docs که باید آپدیت بشن:
- `docs/claude-design.md` — راهنمای designer، باید دستورات `designer-start` رو از `claude-server` هم داشته باشه
- `README.md` (اگر ساخته بشه) — نصب سریع

---

## قوانین نگهداری

> هر بار که یه hook، اسکریپت، یا config تغییر کرد، `commands/install.sh` و `commands/add-user.sh` باید اپدیت بشن تا تغییر رو deploy کنن.

این قانون باید در `CLAUDE.md` هم مستند بشه.

---

## اسکریپت‌های قدیمی

بعد از پیاده‌سازی، این فایل‌ها deprecated می‌شن (نه حذف):

| قدیمی | جایگزین |
|-------|---------|
| `server-setup.sh` | `claude-server install` |
| `setup-new-user.sh` | `claude-server add-user` |
| `install-designer-deps.sh` | بخشی از `claude-server install` |
| `setup-designer.sh` | بخشی از `claude-server install` |
| `check-users.sh` | `claude-server verify` |
| `deploy-fixes.sh` | `claude-server install` (idempotent) |
