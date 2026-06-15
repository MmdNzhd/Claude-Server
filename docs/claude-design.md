# Claude Design — راهنمای کامل

## چیست؟

Claude Design یک محیط مرور مشترک روی سرور است که به طراحان اجازه می‌دهد با fingerprint سرور (نه laptop خود) به claude.ai/design متصل شوند. یک Chrome session مشترک روی سرور وجود دارد که همه طراحان به آن وصل می‌شوند.

## معماری

```
Windows (laptop)
  └─ connect-design.bat / connect-design.ps1
       ├─ SSH → designer@server  →  designer-start start W H
       │                              ├─ Xvfb :UID  (virtual display — 4K max)
       │                              ├─ x11vnc      (VNC server)
       │                              ├─ websockify  (WebSocket bridge)
       │                              └─ Chrome      (claude.ai/design) ← هیچوقت بسته نمیشه
       └─ SSH Tunnel  localhost:6080 → server:NOVNC_PORT
            └─ Edge/Chrome  →  noVNC  →  VNC  →  Chrome روی سرور
```

## یوزر مشترک

همه طراحان با یوزر **`designer`** وصل می‌شوند. فقط یک نفر در هر لحظه می‌تواند کار کند. اگر نفر دوم وصل شود، نفر اول **kick** می‌شود و پیام می‌گیرد. نفر اول می‌تواند با R دوباره session را پس بگیرد.

## پورت‌بندی

| سرویس | پورت |
|-------|------|
| VNC | 25000 + UID |
| noVNC / websockify | 26000 + UID |
| SSH tunnel (client) | 6080 (ثابت) |

## نصب اولیه روی سرور (یک بار)

```bash
# ۱. نصب dependencies
sudo bash scripts/server/install-designer-deps.sh

# ۲. ساخت یوزر designer و نصب اسکریپت
sudo bash scripts/server/setup-designer.sh

# ۳. اضافه کردن SSH key هر طراح
sudo bash scripts/server/setup-designer.sh --add-key "ssh-ed25519 AAAA..."
```

## اضافه کردن SSH key طراح جدید

```bash
sudo bash scripts/server/setup-designer.sh --add-key "$(cat /path/to/key.pub)"
```

## اتصال از Windows

فایل‌های مورد نیاز (کنار هم):
- `scripts/client/windows/connect-design.bat`
- `scripts/client/windows/connect-design.ps1`

دابل‌کلیک روی `connect-design.bat` — همه چیز اتوماتیک انجام می‌شود.

## اولین اتصال (login)

Chrome روی سرور باز می‌شود. **یک بار** لاگین به claude.ai انجام دهید. بعد از آن session برای همه طراحان ذخیره است.

برای خروج از kiosk mode: `Alt+F4` — بعد bat را دوباره بزنید.

## رفتار Chrome

- Chrome روی سرور **هیچوقت** بسته نمی‌شود (حتی وقتی کسی وصل نیست)
- وقتی یک طراح وصل می‌شود، همان Chrome موجود را می‌بیند
- session، تب‌ها، و login همیشه محفوظ است
- Chrome profile در `/opt/chrome-design-profile` ذخیره است (مشترک بین همه)

## رفتار resolution

- `connect-design.ps1` اندازه مانیتور اصلی را می‌خواند
- Xvfb با حداکثر اندازه (4K) شروع می‌شود
- `xrandr` resolution را به اندازه واقعی مانیتور تنظیم می‌کند — بدون restart Chrome
- اگر xrandr کار نکند، فقط Xvfb/x11vnc/websockify restart می‌شوند (نه Chrome)

## مکانیزم kick

وقتی طراح B وصل می‌شود در حالی که A متصل است:
1. B پیام **"Previous user was disconnected"** می‌بیند
2. websockify A کشته می‌شود → tunnel A قطع می‌شود
3. A پیام **"You were disconnected by another designer"** می‌بیند
4. A می‌تواند R بزند تا session را پس بگیرد (که B را kick می‌کند)
5. Chrome روی سرور در تمام این مراحل **روشن می‌ماند**

## تنظیمات noVNC

```
http://localhost:6080/vnc.html?autoconnect=true&resize=none&quality=9&compression=0&reconnect=true&reconnect_delay=2000&view_only=0
```

| پارامتر | مقدار | توضیح |
|---------|-------|-------|
| resize | none | بدون scale |
| quality | 9 | بالاترین کیفیت |
| compression | 0 | بدون فشرده‌سازی (شبکه داخلی) |
| reconnect | true | auto-reconnect داخل browser |
| reconnect_delay | 2000 | هر 2 ثانیه retry |
| view_only | 0 | mouse و keyboard فعال |

## به‌روزرسانی designer-start

بعد از هر تغییر در `scripts/server/designer-start.sh`:

```bash
sudo install -m 755 /home/smart/mounts/claude-code-server/scripts/server/designer-start.sh /usr/local/bin/designer-start
```

## مدیریت سرور با claude-server CLI

```bash
# نصب روی سرور جدید (یک‌بار)
git clone <repo> && sudo bash scripts/server/claude-server install

# اضافه کردن developer جدید
sudo claude-server add-user <username>

# بررسی سلامت همه components
claude-server verify

# وضعیت sessions فعال + usage + token cost
claude-server status

# راهنما
claude-server --help
```

## دستورات مدیریتی (روی سرور)

```bash
# وضعیت session
sudo -u designer designer-start status

# توقف کامل (Chrome هم بسته می‌شود)
sudo -u designer designer-start stop

# شروع دستی با resolution مشخص
sudo -u designer designer-start start 1920 1080

# بررسی process ها
ps aux | grep designer | grep -E "Xvfb|x11vnc|websockify|chrome" | grep -v grep

# لاگ session
tail -f /home/designer/.designer/session.log

# اضافه کردن SSH key
echo "ssh-ed25519 AAAA..." >> /home/designer/.ssh/authorized_keys
```

## رندرینگ Chrome (SwiftShader)

چون سرور GPU فیزیکی ندارد، Chrome با software rendering کار می‌کند. فلگ‌های مورد نیاز در `designer-start.sh`:

```bash
--use-gl=angle
--use-angle=swiftshader-webgl
--enable-unsafe-swiftshader
```

**توجه:** فلگ قدیمی `--use-gl=swiftshader` از Chrome 130 به بعد deprecated و از Chrome 139 کاملاً حذف شده. استفاده از آن ANGLE را از pipeline گرافیکی حذف می‌کند و WebGL کار نمی‌کند.

## عیب‌یابی

### chat box باز نمی‌شود / صفحه design لود نمی‌شود
مشکل permission روی Chrome profile یا `.local/share`:
```bash
# نشانه در log:
# Failed to open persistent cache files ... Permission denied
# ContextResult::kTransientFailure: Failed to send GpuControl.CreateCommandBuffer

sudo chown -R designer:designer /opt/chrome-design-profile
sudo chmod -R 755 /opt/chrome-design-profile
sudo mkdir -p /home/designer/.local/share
sudo chown -R designer:designer /home/designer/.local
designer-start stop && designer-start start 1920 1080
```

### "ERROR: another start in progress"
یک lock file مانده. پاک کن:
```bash
rm -f /home/designer/.designer/start.lock
```

### noVNC keeps reconnecting
x11vnc یا websockify کرش کرده:
```bash
pkill -u designer x11vnc; pkill -u designer websockify
sudo -u designer designer-start start 1920 1080
```

### Chrome پروفایل جدید باز کرد
Singleton lock مانده:
```bash
rm -f /opt/chrome-design-profile/SingletonLock /opt/chrome-design-profile/SingletonSocket /opt/chrome-design-profile/SingletonCookie
```

### صفحه سیاه
x11vnc بالا نیامده:
```bash
pkill -u designer x11vnc
sudo -u designer designer-start start 1920 1080
```

### SSH key تایید نمی‌شود
```bash
sudo bash scripts/server/setup-designer.sh --add-key "$(cat ~/.ssh/id_ed25519.pub)"
```

### سرور host key تغییر کرده
PowerShell script خودکار handle می‌کند. اگر دستی لازم شد:
```powershell
ssh-keygen -R 192.168.210.240
```

## فضای دیسک

- Chrome profile: `/opt/chrome-design-profile` (مشترک)
- لاگ session: `/home/designer/.designer/session.log` (حداکثر 500KB نگه می‌دارد)
- RAM مصرفی هر session: حدود 200-400MB
