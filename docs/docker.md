# Docker

Run AntGain in a container using the image [pinors/antgain-cli](https://hub.docker.com/r/pinors/antgain-cli) on Docker Hub.

**API key:** [antgain.app → Settings](https://antgain.app/dashboard/settings)

---

## Device UUID (`ANTGAIN_DEVICE_ID`)

Each container is one node on the server. The platform binds that node to a **UUID** you choose.

| Do | Don't |
|----|--------|
| Generate a UUID **once** and save it in `.env` or Compose | Put `ANTGAIN_DEVICE_ID=$(uuidgen ...)` in every `docker run` |
| Reuse the **same** UUID when you recreate **this** container | Generate a new UUID on each restart |
| Use a **different** UUID for each container running **at the same time** | Share one UUID between two running containers |

Generate a UUID once:

```bash
uuidgen | tr '[:upper:]' '[:lower:]'
# Example: f6fdbd41-4e2c-4a1b-9c3d-8e7f6a5b4c2d
```

Write it in `.env` and keep that file. That value is the node’s identity on AntGain.

**Required:** every container must have `ANTGAIN_API_KEY` and `ANTGAIN_DEVICE_ID` (standard UUID format).

If the container already has `~/.antgain/config.json` with a saved id, **`ANTGAIN_DEVICE_ID` in the environment still wins**. Do not pass a new random UUID on restart — use the same value as the first time you created this node.

Check device id:

```bash
docker exec -it antgain-node antgain info
```

---

## Quick start

Create `.env` (generate the UUID only when you create a **new** node):

```bash
ANTGAIN_API_KEY=your_api_key_here
ANTGAIN_DEVICE_ID=f6fdbd41-4e2c-4a1b-9c3d-8e7f6a5b4c2d
```

```bash
docker run -d \
  --name antgain-node \
  --restart unless-stopped \
  --env-file .env \
  pinors/antgain-cli:latest
```

```bash
docker logs -f antgain-node
docker exec -it antgain-node antgain status
docker exec -it antgain-node antgain logs -f
```

---

## Docker Compose

```yaml
services:
  antgain-node:
    image: pinors/antgain-cli:latest
    container_name: antgain-node
    restart: unless-stopped
    env_file: .env
```

```bash
docker compose up -d
docker compose logs -f
```

---

## Recreate or upgrade (same node)

Keep the **same** `ANTGAIN_DEVICE_ID` for this node. Do not generate a new UUID on upgrade.

### Docker Compose

Pull the latest image for your tag, then recreate the service:

```bash
docker compose pull
docker compose up -d
```

You can use `docker compose down` first if you prefer a full teardown; `up -d` alone is enough when only the image changed.

### `docker run` — one-line upgrade script

If the container was created with `docker run` (not Compose), use the upgrade script. It resolves the image repository from the running container, **always pulls `:latest`**, copies environment variables and run options from the old container, starts a new container with the same name, and keeps the old one as a backup. If the new container fails to start, it rolls back automatically.

```bash
curl -fsSL https://install.antgain.app/docker-update.sh | bash -s -- antgain-node
```

Replace `antgain-node` with your container name.

**What the script does**

1. Export env vars from the running container (including `ANTGAIN_API_KEY` and `ANTGAIN_DEVICE_ID`)
2. `docker pull` for `<repository>:latest` (ignores the tag the container was using, e.g. `v1.0.0` → `latest`)
3. Stop the old container and rename it to `<name>_backup_<timestamp>`
4. Start a new container with the same name and configuration
5. Check that it is running; on failure, restore the backup

**After a successful upgrade**

Confirm the node is healthy, then remove the backup container:

```bash
docker exec -it antgain-node antgain status
docker rm antgain-node_backup_YYYYMMDD_HHMMSS
```

**Manual rollback** (if you need to revert after confirming the upgrade):

```bash
docker stop antgain-node
docker rm antgain-node
docker rename antgain-node_backup_YYYYMMDD_HHMMSS antgain-node
docker start antgain-node
```

**Notes**

| Topic | Detail |
|-------|--------|
| Scope | For containers created with `docker run`. Use Compose commands above for Compose-managed services. |
| Image tag | Always upgrades to `:latest` for the same repository (e.g. `pinors/antgain-cli:v1.0.0` → `pinors/antgain-cli:latest`). To stay on a pinned tag, recreate the container manually. |
| Custom setup | Works best for the default AntGain layout (`--env-file`, `--restart`, simple mounts). Unusual `docker run` flags may not be copied. |
| Dependencies | Requires `docker` and `jq` (the script tries to install `jq` on apt/yum/dnf systems when run as root). |

### `docker run` — manual recreate

Stop and remove the container, then start again with the **same** `.env` file:

```bash
docker pull pinors/antgain-cli:latest
docker stop antgain-node
docker rm antgain-node
docker run -d \
  --name antgain-node \
  --restart unless-stopped \
  --env-file .env \
  pinors/antgain-cli:latest
```

---


## Multiple nodes on one host

Each service needs its own `ANTGAIN_DEVICE_ID` in `.env` or in the Compose file. Never run two containers with the same UUID at once.

---

## Environment variables

| Variable | Required | Description |
|----------|----------|-------------|
| `ANTGAIN_API_KEY` | Yes | Your API key |
| `ANTGAIN_DEVICE_ID` | Yes | Fixed UUID for this container (see above) |
| `ANTGAIN_AUTO_UPDATE_ON_RECONNECT` | No | Default on; set to `0` to disable in-container update check on reconnect |
| `ANTGAIN_SKIP_UPDATE_ON_RECONNECT` | No | Set to `1` to disable reconnect updates |

---

## Logs

| What | Command |
|------|---------|
| Container output | `docker logs -f antgain-node` |
| Audit log inside container | `docker exec -it antgain-node antgain logs -f` |

CLI command reference: [commands.md](commands.md).

---

## Troubleshooting

**Cannot connect after recreate** — you changed `ANTGAIN_DEVICE_ID`. Use the original UUID from your `.env`.

**Two containers conflict** — duplicate `ANTGAIN_DEVICE_ID`. Give each container its own UUID.

**Missing `ANTGAIN_DEVICE_ID`** — Docker nodes must set it; the process will not start without a valid UUID.

**Upgrade script failed or rolled back** — Check `docker logs antgain-node`. The backup container (`<name>_backup_<timestamp>`) is still on the host; use the manual rollback steps in [Recreate or upgrade](#recreate-or-upgrade-same-node) if needed.

---

## Linux or macOS install

Use the host installer instead of Docker: [linux.md](linux.md) · [macos.md](macos.md)

---

[← Back to index](../README.md)
