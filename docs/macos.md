# macOS

Install the CLI on an Intel or Apple Silicon Mac.

## Install

Sign in at [AntGain](https://antgain.app), open [Account Settings](https://antgain.app/dashboard/settings), and copy your **API Key**. Click **Generate API Key** if needed.

Replace `PASTE_YOUR_API_KEY_HERE` and run:

```bash
curl -fsSL https://install.antgain.app/install-cli.sh | ANTGAIN_API_KEY='PASTE_YOUR_API_KEY_HERE' bash
```

The script downloads the latest release, verifies its SHA-256, and selects the correct build for your Mac. With administrator access it installs a LaunchDaemon and starts the node. Without administrator access it installs under `~/.local/bin` and starts a background process.

For a specific release, use `VERSION=1.1.4` before `bash` in the command above. A device ID is generated on first start and preserved during updates and reinstalls.

## Check and manage your node

For a system service:

```bash
sudo /usr/local/sbin/antgain-service check
sudo /usr/local/sbin/antgain-service status
sudo launchctl print system/app.antgain.cli
sudo launchctl kickstart -k system/app.antgain.cli
antgain logs -f
```

System services save data under `/var/lib/antgain`. User installations save credentials and identity under `~/.antgain`. A user background process does not start automatically after reboot.

To run manually:

```bash
export ANTGAIN_API_KEY='PASTE_YOUR_API_KEY_HERE'
antgain run --daemon
unset ANTGAIN_API_KEY
```

Open [your dashboard](https://antgain.app/dashboard) to see your devices and earnings.

## Update or uninstall

For a user installation, run `antgain update`. For a system service:

```bash
sudo env ANTGAIN_DATA_DIR=/var/lib/antgain antgain update
```

Uninstall:

```bash
curl -fsSL https://install.antgain.app/uninstall-cli.sh | bash
```

Saved data is preserved unless you choose to delete it.

## If macOS blocks the program

Open **System Settings → Privacy & Security** and allow AntGain if prompted.

[CLI commands](commands.md) · [Docker](docker.md) · [Back to index](../README.md)
