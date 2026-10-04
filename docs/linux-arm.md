# Linux ARM

The CLI supports Linux ARM64 (`aarch64`) and ARMv7 (`armhf`) systems, including supported Debian and Ubuntu installations on ARM boards.

## Install

Sign in at [AntGain](https://antgain.app), open [Account Settings](https://antgain.app/dashboard/settings), and copy your **API Key**. Click **Generate API Key** if needed.

Replace `PASTE_YOUR_API_KEY_HERE` and run:

```bash
curl -fsSL https://install.antgain.app/install-cli.sh | ANTGAIN_API_KEY='PASTE_YOUR_API_KEY_HERE' bash
```

The script selects the build for your system. The device ID is generated and saved automatically. Keep the saved data when updating or reinstalling.

For systems without systemd, the installer uses OpenRC, SysV, or a startup helper where available:

```bash
sudo /usr/local/sbin/antgain-service status
sudo /usr/local/sbin/antgain-service stop
sudo /usr/local/sbin/antgain-service start
```

System services save data under `/var/lib/antgain`; user installations use `~/.antgain`.

See [Linux](linux.md) for service management, updates, and uninstall instructions, or [Docker](docker.md) to run in a container.

[Back to index](../README.md)
