# Windows

The Windows CLI supports Windows 10, Windows 11, and Windows Server on x64 systems.

## Get your API key

Sign in at [AntGain](https://antgain.app), open [Account Settings](https://antgain.app/dashboard/settings), and copy your **API Key**. Click **Generate API Key** if you do not have one yet.

## Install

Open PowerShell, replace `PASTE_YOUR_API_KEY_HERE`, and run:

```powershell
$env:ANTGAIN_API_KEY = "PASTE_YOUR_API_KEY_HERE"
irm https://install.antgain.app/install.ps1 | iex
Remove-Item Env:ANTGAIN_API_KEY
```

The installer downloads the latest release, checks its SHA-256, adds `antgain` to your user PATH, and starts the node in the background. The client saves credentials and generates a device ID automatically. Installing again keeps the same device ID.

To install without starting, set `$env:ANTGAIN_SKIP_START = "1"` before running the installer. Remove that variable afterwards with `Remove-Item Env:ANTGAIN_SKIP_START`.

If you need a specific release, set `$env:VERSION = "1.1.4"` before running the installer. Remove it afterwards with `Remove-Item Env:VERSION`.

## Everyday commands

```powershell
antgain check
antgain status
antgain logs -f
antgain start -d
antgain stop
antgain restart
antgain update
```

Closing PowerShell does not stop a background node. This installer does not register Windows startup; after reboot, run `antgain start -d` again.

Open [your dashboard](https://antgain.app/dashboard) to see your devices and earnings. Keep API keys private when sharing screenshots or logs.

## Uninstall

```powershell
irm https://install.antgain.app/uninstall.ps1 | iex
```

Saved credentials, device identity, and logs are preserved unless you choose to delete them.

To remove saved data as well:

```powershell
$env:ANTGAIN_UNINSTALL_PURGE = "1"
irm https://install.antgain.app/uninstall.ps1 | iex
Remove-Item Env:ANTGAIN_UNINSTALL_PURGE
```

[CLI commands](commands.md) · [Back to index](../README.md)
