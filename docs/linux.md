# Linux

Install the CLI on a Linux x64 computer, server, or VPS. For ARM devices, see [Linux ARM](linux-arm.md).

## Get your API key

Sign in at [AntGain](https://antgain.app), open [Account Settings](https://antgain.app/dashboard/settings), and copy your **API Key**. Click **Generate API Key** if you do not have one yet.

## Install

Replace `PASTE_YOUR_API_KEY_HERE` and run:

```bash
curl -fsSL https://install.antgain.app/install-cli.sh | ANTGAIN_API_KEY='PASTE_YOUR_API_KEY_HERE' bash
```

The installer downloads the latest release and verifies its SHA-256. With administrator access it installs a background service and starts the node. Without administrator access it installs under `~/.local/bin` and uses a user service or background process. Open a new terminal if `antgain` is not yet on your PATH.

A device ID is generated on first start. Reinstalling or updating keeps the saved identity.

To download the CLI without installing a service:

```bash
curl -fsSL https://install.antgain.app/install-cli.sh | ANTGAIN_SKIP_START=1 bash
```

To install a specific release:

```bash
curl -fsSL https://install.antgain.app/install-cli.sh | VERSION=1.1.4 ANTGAIN_API_KEY='PASTE_YOUR_API_KEY_HERE' bash
```

## Check your node

```bash
antgain check
antgain status
antgain logs -f
```

For a system service, use its saved settings when checking your account:

```bash
sudo /usr/local/sbin/antgain-service check
sudo /usr/local/sbin/antgain-service status
```

Open [your dashboard](https://antgain.app/dashboard) to see devices and earnings.

## Manage the background service

On systems with systemd:

```bash
sudo systemctl status antgain
sudo systemctl restart antgain
sudo systemctl stop antgain
sudo systemctl start antgain
```

For a user service, use `systemctl --user` instead. A user service normally starts after login. An administrator can enable startup before login with `sudo loginctl enable-linger "$USER"`.

On systems without systemd:

```bash
sudo /usr/local/sbin/antgain-service start
sudo /usr/local/sbin/antgain-service stop
sudo /usr/local/sbin/antgain-service status
```

System services save node data under `/var/lib/antgain`. Their program files are stored under `/usr/local/lib/antgain` so the node can apply updates. The `antgain` command remains available in `/usr/local/bin`.

## Run manually

```bash
export ANTGAIN_API_KEY='PASTE_YOUR_API_KEY_HERE'
antgain run --daemon
unset ANTGAIN_API_KEY
```

User installations save credentials and identity under `~/.antgain`. Do not delete this directory if you want to keep the same node.

## Update or uninstall

For a user installation:

```bash
antgain update
```

For a system service:

```bash
sudo env ANTGAIN_DATA_DIR=/var/lib/antgain antgain update
```

To uninstall either kind:

```bash
curl -fsSL https://install.antgain.app/uninstall-cli.sh | bash
```

The uninstaller requests administrator access if a system installation exists. Saved data is preserved unless you choose to delete it. Docker containers are removed separately using Docker commands.

[CLI commands](commands.md) · [Docker](docker.md) · [Back to index](../README.md)
