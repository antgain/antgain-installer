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

## `antgain run`

Start the node.

| Option | Short | Description |
|--------|-------|-------------|
| `--daemon` | `-d` | Run in the background (detached from this terminal) |
| `--server <HOST:PORT>` | — | Use a specific QUIC server address instead of the one from the API (rare; leave unset in normal use) |

Examples:

```bash
antgain run
antgain run --daemon
antgain run --api-key YOUR_KEY -d
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

Shows local node information: CLI version, device id, whether credentials are saved, config path, and related details.

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

On Linux with a **systemd** service, if no log file is found, the command may use `journalctl -u antgain` instead.

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

## `antgain update`

Downloads a newer CLI from the release channel when available, replaces the binary, and restarts the node if it was running.

```bash
antgain update
```

---

## `antgain logout`

Clears saved API credentials on this machine.

```bash
antgain logout
```

---

## Quick reference

| Command | Purpose |
|---------|---------|
| `antgain` | Start node (foreground) |
| `antgain run [-d]` | Start node; `-d` = background |
| `antgain stop` | Stop node |
| `antgain restart` | Restart node |
| `antgain status [--format json]` | Status and earnings |
| `antgain info` | Local configuration |
| `antgain logs [-n N] [-f]` | View audit log |
| `antgain update` | Upgrade CLI |
| `antgain logout` | Clear saved API key |

---

[← Back to index](../README.md)
