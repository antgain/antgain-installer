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

Stop and remove the container, then start again with the **same** `.env` — do not change `ANTGAIN_DEVICE_ID`.

```bash
docker compose down
docker compose pull
docker compose up -d
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

---

## Linux or macOS install

Use the host installer instead of Docker: [linux.md](linux.md) · [macos.md](macos.md)

---

[← Back to index](../README.md)
