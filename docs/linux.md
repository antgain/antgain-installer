# Linux (x86_64)

Install the AntGain CLI on Ubuntu, Debian, and other 64-bit x86 Linux systems.

**API key:** [antgain.app → Settings](https://antgain.app/dashboard/settings)

---

## Install

```bash
curl -fsSL https://install.antgain.app/install-cli.sh | bash -s -- YOUR_API_KEY
```

This installs `antgain` to `/usr/local/bin`, sets up **start on boot** when possible, and starts the node.

Pin a version:

```bash
curl -fsSL https://install.antgain.app/install-cli.sh | bash -s -- 1.1.0 YOUR_API_KEY
```

Use `bash -s --` before the version and API key.

---

## Install options

| Goal | How |
|------|-----|
| Latest release | `curl -fsSL https://install.antgain.app/install-cli.sh \| bash` |
| API key + service | `bash -s -- YOUR_API_KEY` |
| Binary only (no service) | `ANTGAIN_SKIP_START=1` with the install script |
| Install service later | `curl -fsSL https://install.antgain.app/install-cli-service.sh \| sudo bash -s -- YOUR_API_KEY` |
| Custom install path | `ANTGAIN_INSTALL_DIR=$HOME/.local/bin` |

| Variable | Effect |
|----------|--------|
| `VERSION=1.1.0` | Pin release (same as `bash -s -- 1.1.0`) |
| `ANTGAIN_API_KEY=...` | Pass API key via environment |
| `ANTGAIN_SKIP_START=1` | Do not install background service |
| `ANTGAIN_AUTO_START=false` | Enable boot start but do not start until reboot |
| `ANTGAIN_NO_BOOT=1` | Install service without enable on boot |

---

## After install

```bash
antgain status
antgain logs -f
```

Device identity is saved automatically in `~/.antgain/config.json`. You do not need to set `ANTGAIN_DEVICE_ID` on Linux unless you want a fixed id yourself.

---

## Service (systemd)

When you install with an API key, a **systemd** service is used if available:

```bash
sudo systemctl status antgain
sudo systemctl restart antgain
antgain logs -f
```

API key (root only): `/etc/antgain/env`

---

## Manual run

```bash
export ANTGAIN_API_KEY=your-key
antgain
antgain run --daemon
```

All commands: [commands.md](commands.md).

---

## Upgrade and remove

```bash
antgain update
```

```bash
curl -fsSL https://install.antgain.app/uninstall-cli.sh | sudo bash
```

---

## Related guides

- [Linux ARM boards](linux-arm.md)  
- [Docker](docker.md)  
- [macOS](macos.md)  
- [CLI commands](commands.md)

Desktop app (graphical, Linux amd64 only):

```bash
curl -fsSL https://install.antgain.app/install-linux.sh | sudo bash
```

---

[← Back to index](../README.md)
