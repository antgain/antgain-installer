# CLI commands

The `antgain` program controls your node after installation. API key: [antgain.app → Settings](https://antgain.app/dashboard/settings).

---

## Global options

Available on every command:

| Option | Environment variable | Description |
|--------|----------------------|-------------|
| `--api-key <KEY>` | `ANTGAIN_API_KEY` | Your API key. If omitted, the CLI uses a key saved from a previous login. |
| `--help` | — | Show help |
| `--version` | — | Show CLI version |

Examples:

```bash
antgain --api-key YOUR_KEY status
export ANTGAIN_API_KEY=YOUR_KEY
antgain status
```

---

## `antgain` (no subcommand)

Starts the node in the **foreground** (terminal must stay open). Same as `antgain run` without `--daemon`.

```bash
antgain
antgain --api-key YOUR_KEY
```

Stops with **Ctrl+C**.

If the installer set `ANTGAIN_SKIP_START` or `ANTGAIN_AUTO_START=false`, bare `antgain` may exit and tell you to run `antgain run` manually.

---

## `antgain run` (or `antgain start`)

Start the node. `antgain start` is a built-in alias for `antgain run`.

| Option | Short | Description |
|--------|-------|-------------|
| `--daemon` | `-d` | Run in the background (detached from this terminal) |

Examples:

```bash
antgain start
antgain start --daemon
antgain start --api-key YOUR_KEY -d
antgain run -d
```

---

## `antgain stop`

Stops a running node (background daemon, systemd, or launchd).

```bash
antgain stop
```

---

## `antgain restart`

Restarts the node.

```bash
antgain restart
```

---

## `antgain status`

Shows whether the node is running and your account summary (balance, traffic, and related stats).

| Option | Description |
|--------|-------------|
| `--format text` | Human-readable panel (default) |
| `--format json` | Machine-readable JSON |

Examples:

```bash
antgain status
antgain status --format json
```

---

## `antgain info`

Shows the installed version, device ID, and local configuration information.

```bash
antgain info
```

---

## `antgain logs`

Shows the node **audit log** (`antgain.log`). Secrets are redacted in the file.

| Option | Short | Description |
|--------|-------|-------------|
| `--lines <N>` | `-n` | Number of lines to show (default: `50`) |
| `--follow` | `-f` | Keep printing new lines (like `tail -f`) |
| `--file <PATH>` | — | Read a specific log file instead of auto-detection |

Examples:

```bash
antgain logs
antgain logs -n 200
antgain logs -f
antgain logs --file /var/lib/antgain/logs/antgain.log
```

For systemd service output, run `sudo journalctl -u antgain -n 50 --no-pager`.

**Docker:**

```bash
docker logs -f antgain-node
docker exec -it antgain-node antgain logs -f
```

Default log file locations:

| Setup | Typical path |
|-------|----------------|
| Manual / user install | `~/.antgain/logs/antgain.log` |
| Linux systemd service | `/var/lib/antgain/logs/antgain.log` |
| macOS launchd service | `/var/log/antgain.log` or `antgain logs` |

---

## `antgain check` (or `antgain doctor`)

Checks your local configuration, saved credentials, network connection, node process, and log files.

```bash
antgain check
antgain doctor
```

---

## `antgain update`

Downloads a newer CLI from the release channel when available, replaces the binary, and restarts the node if it was running.

```bash
antgain update
```

---

## `antgain configure`

Save an API key without starting the node. The client preserves the existing device identity and stores the key in its configuration format.

```bash
ANTGAIN_API_KEY='PASTE_YOUR_API_KEY_HERE' antgain configure
```

This command is available in the updated CLI. It saves the key locally; use `antgain check` to verify the account and connection.

---

## `antgain logout`

Clears saved API credentials on this machine.

```bash
antgain logout
```

---

## `antgain uninstall`

Removes the CLI and supported background service registrations. For installations created by the one-line installer, use the uninstall command in the [Linux](linux.md), [macOS](macos.md), or [Windows](windows.md) guide so its helper files are removed too. Saved data is deleted only when requested.

| Option | Short | Description |
|--------|-------|-------------|
| `--purge` | `-p` | Purge data, credentials, and log directories (`~/.antgain`) |
| `--yes` | `-y` | Automatic confirmation without prompt |

```bash
antgain uninstall
antgain uninstall --purge -y
```

---

## `antgain health`

Checks whether the node is running and connected. Exit code `0` means healthy; `1` means the node is unavailable or its connection needs attention. Docker uses this command for health checks.

```bash
antgain health
```

Output:
- `healthy` (exit code 0)
- `unhealthy: <reason>` (exit code 1)

---

## Quick reference

| Command | Purpose |
|---------|---------|
| `antgain` | Start node (foreground) |
| `antgain start [-d]` | Start node (alias of `run`); `-d` = background |
| `antgain check` | Run diagnostics & health check (alias `doctor`) |
| `antgain stop` | Stop node |
| `antgain restart` | Restart node |
| `antgain status [--format json]` | Status and earnings |
| `antgain info` | Local configuration |
| `antgain logs [-n N] [-f]` | View audit log |
| `antgain health` | Health check for Docker (exits 0 if healthy, 1 if unhealthy) |
| `antgain update` | Upgrade CLI |
| `antgain uninstall` | Uninstall CLI & remove services |
| `antgain configure` | Save an API key without starting |
| `antgain logout` | Clear saved API key |

---

[← Back to index](../README.md)
