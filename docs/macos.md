# macOS

Install and run the AntGain CLI on Intel or Apple Silicon Macs.

**API key:** [antgain.app → Settings](https://antgain.app/dashboard/settings)

---

## Install

```bash
curl -fsSL https://install.antgain.app/install-cli.sh | bash -s -- YOUR_API_KEY
```

Pin version:

```bash
curl -fsSL https://install.antgain.app/install-cli.sh | bash -s -- 1.1.0 YOUR_API_KEY
```

Service only (if CLI is already installed):

```bash
curl -fsSL https://install.antgain.app/install-cli-service.sh | sudo bash -s -- YOUR_API_KEY
```

---

## After install

```bash
antgain status
antgain logs -f
```

Credentials and device id are stored under `~/.antgain/`.

---

## Background service

With an API key, a **LaunchDaemon** starts the node on boot:

```bash
antgain logs -f
```

---

## If macOS blocks the app

```bash
xattr -d com.apple.quarantine /usr/local/bin/antgain 2>/dev/null || true
/usr/local/bin/antgain --version
```

Allow **antgain** in **System Settings → Privacy & Security** if asked.

---

## Manual run

```bash
export ANTGAIN_API_KEY=your-key
antgain
```

[CLI commands](commands.md) · [Uninstall](../README.md) (see Linux guide uninstall script with `sudo`)

---

[← Back to index](../README.md) · [Docker](docker.md)
