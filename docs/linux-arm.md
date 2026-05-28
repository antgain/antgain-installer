# Linux ARM

For boards such as RK3528 / RK3576 and other ARM SBCs running Debian or Ubuntu.

**API key:** [antgain.app → Settings](https://antgain.app/dashboard/settings)

---

## Which build

| System | Use |
|--------|-----|
| 64-bit (aarch64) | Same installer as [Linux x86_64](linux.md) |
| 32-bit (armhf) | Same installer; the script picks `linux-armv7` |

---

## Install

```bash
curl -fsSL https://install.antgain.app/install-cli.sh | bash -s -- YOUR_API_KEY
```

```bash
antgain status
```

Identity is stored in `~/.antgain/config.json` after the first run.

---

## No systemd

On many ARM images there is no systemd. The installer may use SysV, OpenRC, or cron `@reboot` instead.

```bash
sudo /usr/local/sbin/antgain-service start
sudo /usr/local/sbin/antgain-service status
antgain logs -f
```

Or:

```bash
export ANTGAIN_API_KEY=your-key
antgain run --daemon
```

If you see “systemd is required”, the CLI is still installed — use the commands above.

---

## CLI commands

[commands.md](commands.md)

---

[← Back to index](../README.md) · [Linux x86_64](linux.md) · [Docker](docker.md)
