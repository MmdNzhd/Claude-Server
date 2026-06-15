# Claude Code Server — Project Rules

## قانون sync اسکریپت‌ها

هر بار که یکی از فایل‌های زیر تغییر کرد، باید فایل‌های deploy هم آپدیت بشن:

| فایل تغییر کرد | باید آپدیت بشه |
|----------------|----------------|
| `scripts/server/hooks/claude-hook-*.sh` | `scripts/server/commands/install.sh` (بخش deploy hooks) |
| `scripts/server/claude-wrapper.sh` | `scripts/server/commands/install.sh` (بخش deploy wrapper) |
| `scripts/server/claude-limits.conf` | `scripts/server/commands/install.sh` (بخش deploy config) |
| `scripts/server/claude-automount.sh` | `scripts/server/commands/install.sh` (بخش deploy scripts) |
| `scripts/server/commands/add-user.sh` | بررسی کن settings.json template هنوز درسته |

هر تغییر در hooks یا wrapper باید با این دستور روی سرور deploy بشه:

```bash
sudo claude-server install
```

این دستور idempotent هست — می‌شه بدون ترس دوباره زد.

## ساختار scripts/server

- `claude-server` — CLI dispatcher (نصب می‌شه روی `/usr/local/bin/claude-server`)
- `commands/` — هر subcommand یه فایل مجزا:
  - `install.sh` — نصب کامل سرور (جایگزین `server-setup.sh` و `install-designer-deps.sh`)
  - `add-user.sh` — اضافه کردن developer (جایگزین `setup-new-user.sh`)
  - `verify.sh` — تست همه components (جایگزین `check-users.sh`)
  - `status.sh` — وضعیت sessions و usage
- `hooks/` — Claude Code hooks (deploy می‌شن روی `/usr/local/bin/`)

## اسکریپت‌های deprecated

این فایل‌ها نگه داشته شدن ولی استفاده نکن:

| قدیمی | جایگزین |
|-------|---------|
| `server-setup.sh` | `claude-server install` |
| `setup-new-user.sh` | `claude-server add-user <name>` |
| `install-designer-deps.sh` | بخشی از `claude-server install` |
| `setup-designer.sh` | بخشی از `claude-server install` |
| `check-users.sh` | `claude-server verify` |
| `deploy-fixes.sh` | `claude-server install` (idempotent) |
