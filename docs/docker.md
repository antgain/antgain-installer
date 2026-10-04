# AntGain Node for Docker

Share unused bandwidth with AntGain using Docker. Install and start Docker first, then follow the steps below in a Linux, macOS, or NAS terminal.

## 1. Get your API key

1. Sign up or sign in at [AntGain](https://antgain.app).
2. Open [Account Settings](https://antgain.app/dashboard/settings) and find **API Key**.
3. Copy your key. If you do not have one yet, click **Generate API Key** first.

Keep your API key private.

Create a folder for your Docker setup:

```bash
mkdir -p antgain-docker
cd antgain-docker
```

Replace `PASTE_YOUR_API_KEY_HERE` with your key, then run:

```bash
cat > antgain.env <<'EOF_KEY'
ANTGAIN_API_KEY=PASTE_YOUR_API_KEY_HERE
EOF_KEY
chmod 600 antgain.env
```

## 2. Start AntGain

```bash
docker run -d \
  --name antgain-node \
  --restart unless-stopped \
  --stop-timeout 30 \
  --health-cmd="antgain health || exit 1" \
  --health-interval=30s \
  --health-timeout=5s \
  --health-start-period=120s \
  --health-retries=3 \
  --env-file ./antgain.env \
  -v antgain-data:/data/.antgain \
  pinors/antgain-cli:latest
```

Docker downloads the image if needed and starts AntGain in the background. Automatic updates are enabled by default; no update setting is needed.

The device ID is generated automatically on first start and saved in `antgain-data`. Keep this volume when restarting, updating, or replacing the container.

## 3. Check your node

```bash
# View recent output
docker logs --tail 100 antgain-node

# Check the node connection
docker exec antgain-node antgain health

# View Docker health status: starting, healthy, or unhealthy
docker inspect --format '{{.State.Health.Status}}' antgain-node
```

Allow up to two minutes for startup. AntGain checks its connection every 30 seconds after this startup period. After three consecutive failed checks, it exits so Docker's `unless-stopped` policy can restart the container. If this repeats, check your API key, internet connection, and logs. Open [your dashboard](https://antgain.app/dashboard) to see your devices, usage, and earnings.

## Everyday commands

```bash
# Follow container output; Ctrl+C closes the log view
docker logs -f antgain-node

# Stop sharing
docker stop antgain-node

# Start sharing again
docker start antgain-node

# Restart the container
docker restart antgain-node

# Show the installed client version
docker exec antgain-node antgain --version
```

### Update the Docker image

Automatic client updates run inside the container. To refresh the Docker image as well, run these commands from your `antgain-docker` folder:

```bash
docker pull pinors/antgain-cli:latest
docker stop antgain-node
docker rm antgain-node

docker run -d \
  --name antgain-node \
  --restart unless-stopped \
  --stop-timeout 30 \
  --health-cmd="antgain health || exit 1" \
  --health-interval=30s \
  --health-timeout=5s \
  --health-start-period=120s \
  --health-retries=3 \
  --env-file ./antgain.env \
  -v antgain-data:/data/.antgain \
  pinors/antgain-cli:latest
```

The same data volume keeps your device ID. Do not delete `antgain-data`.

## Optional: set your own device ID

You normally do not need to do this. Only two environment variables are needed for this setup:

| Variable | Required | Description |
|----------|----------|-------------|
| `ANTGAIN_API_KEY` | Yes | Copy it from Account Settings. |
| `ANTGAIN_DEVICE_ID` | No | A UUID for this node. Leave it unset to generate and save one automatically. |

If you want to specify an ID **before starting a new node**, generate a UUID:

```bash
docker run --rm --entrypoint cat pinors/antgain-cli:latest \
  /proc/sys/kernel/random/uuid
```

Replace `PASTE_UUID_HERE` with the UUID printed by that command, then add it to `antgain.env`:

```bash
printf 'ANTGAIN_DEVICE_ID=%s\n' 'PASTE_UUID_HERE' >> antgain.env
```

Generate it once and keep it unchanged for that node. Each additional node needs its own container name, data volume, and device ID.

If you change `antgain.env`, recreate the container using the commands in **Update the Docker image** so it reads the new settings.

## Optional: Docker Compose

Use Compose **instead of** the `docker run` setup. In your `antgain-docker` folder, keep the same `antgain.env` and create `compose.yaml`:

```bash
cat > compose.yaml <<'EOF_COMPOSE'
services:
  antgain-node:
    image: pinors/antgain-cli:latest
    container_name: antgain-node
    restart: unless-stopped
    stop_grace_period: 30s
    healthcheck:
      test: ["CMD-SHELL", "antgain health || exit 1"]
      interval: 30s
      timeout: 5s
      start_period: 120s
      retries: 3
    env_file:
      - ./antgain.env
    volumes:
      - antgain-data:/data/.antgain

volumes:
  antgain-data:
    name: antgain-data
EOF_COMPOSE
```

If you already started `antgain-node` with `docker run`, remove that container first. Its data volume is kept:

```bash
docker stop antgain-node
docker rm antgain-node
```

Then start with Compose:

```bash
docker compose up -d
```

Run these commands from the same folder:

```bash
# View output
docker compose logs -f antgain-node

# Stop / start / restart
docker compose stop
docker compose start
docker compose restart

# Update the image and recreate the container
docker compose pull
docker compose up -d --force-recreate
```

Keep the data volume. Do not use `docker compose down -v` unless you intend to delete this node's saved data.

## Need help?

If the node cannot connect, check your internet connection and API key, then read `docker logs --tail 100 antgain-node`. After correcting the key in `antgain.env`, recreate the container to apply it.

Visit the [Help Center](https://antgain.app/help) or [contact support](https://antgain.app/contact). Remove API keys and personal information from screenshots or logs before sharing them.
