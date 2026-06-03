# ساختار اسکریپت‌ها

```
scripts/
├── server/                  ← روی سرور (با root) اجرا می‌شود
│   ├── server-setup.sh          نصب کامل سرور از صفر (Node, Claude, sshfs, automount, ...)
│   ├── setup-new-user.sh        افزودن یوزر جدید + کلیدها + hook اتومَونت
│   ├── claude-automount.sh      → /usr/local/bin/claude-automount (mount خودکار idempotent)
│   ├── sync-claude-creds.sh     sync کردن credentials از smart به همه (cron)
│   ├── install-logging.sh       نصب logging + limits + hooks + claude-status
│   ├── claude-wrapper.sh        wrapper روی /usr/local/bin/claude (session limit)
│   ├── claude-status.sh         نمایش وضعیت real-time sessions
│   ├── claude-limits.conf       محدودیت per-user (نسخهٔ مرجع — روی سرور /etc/claude-limits.conf)
│   ├── setup-claude-auth.sh     (قدیمی) تنظیم API key مشترک
│   ├── fix-permissions.sh       اصلاح پرمیشن home ها
│   └── hooks/                   نسخهٔ مرجع hookها (install-logging خودش تولیدشان می‌کند)
│       ├── claude-hook-pre.sh
│       ├── claude-hook-stop.sh
│       └── claude-hook-logout-block.sh
│
└── client/                  ← روی لپ‌تاپ توسعه‌دهنده اجرا می‌شود
    ├── windows/
    │   ├── connect.bat          دابل‌کلیک (پیشنهادی)
    │   ├── connect.ps1          موتور اصلی (connect.bat صدایش می‌زند)
    │   └── mount-my-project.ps1 (قدیمی) mount دستی
    └── mac/                     (مک و لینوکس)
        ├── connect.sh           اتصال یک‌کلیکی
        └── mount-my-project.sh  (قدیمی) mount دستی
```

## نکات
- **توسعه‌دهنده فقط به `client/` نیاز دارد** — ویندوز: `client/windows/connect.bat` ، مک/لینوکس: `client/mac/connect.sh`.
- **ادمین `server/` را اجرا می‌کند** (با root).
- `server-setup.sh` انتظار دارد `claude-automount.sh` کنار خودش (در `server/`) باشد.
- زبان همهٔ کدها انگلیسی است؛ فارسی فقط در داک‌ها (`.md`).
