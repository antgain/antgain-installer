#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="${1:-}"

if [ -z "$CONTAINER_NAME" ]; then
  echo "Usage:"
  echo "  curl -fsSL <script_url> | bash -s -- <container_name>"
  echo
  echo "Example:"
  echo "  curl -fsSL https://install.antgain.app/docker-update.sh | bash -s -- antgain-node"
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: Docker is not installed."
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is not installed. Installing jq..."

  if command -v apt >/dev/null 2>&1; then
    apt update && apt install -y jq
  elif command -v yum >/dev/null 2>&1; then
    yum install -y jq
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y jq
  else
    echo "Error: cannot install jq automatically. Please install jq manually."
    exit 1
  fi
fi

if ! docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  echo "Error: container does not exist: $CONTAINER_NAME"
  exit 1
fi

IMAGE="$(docker inspect "$CONTAINER_NAME" --format '{{.Config.Image}}')"
BACKUP_NAME="${CONTAINER_NAME}_backup_$(date +%Y%m%d_%H%M%S)"
TMP_DIR="/tmp/docker-upgrade-${CONTAINER_NAME}-$$"
ENV_FILE="$TMP_DIR/env.list"

mkdir -p "$TMP_DIR"

echo "========================================"
echo "Container upgrade started"
echo "========================================"
echo "Container name : $CONTAINER_NAME"
echo "Image          : $IMAGE"
echo "Backup name    : $BACKUP_NAME"
echo "========================================"
echo

echo "1. Exporting environment variables..."
docker inspect "$CONTAINER_NAME" \
  --format='{{range .Config.Env}}{{println .}}{{end}}' > "$ENV_FILE"

echo "2. Pulling latest image for the original image tag..."
docker pull "$IMAGE"

echo "3. Reading old container configuration..."

PORT_ARGS="$(docker inspect "$CONTAINER_NAME" | jq -r '
  .[0].HostConfig.PortBindings // {}
  | to_entries[]?
  | .key as $containerPort
  | .value[]?
  | if .HostIp == "" or .HostIp == "0.0.0.0" then
      "-p \(.HostPort):\($containerPort)"
    else
      "-p \(.HostIp):\(.HostPort):\($containerPort)"
    end
')"

MOUNT_ARGS="$(docker inspect "$CONTAINER_NAME" | jq -r '
  .[0].Mounts[]?
  | if .Type == "bind" then
      "-v \(.Source):\(.Destination)\(if .RW then "" else ":ro" end)"
    elif .Type == "volume" then
      "-v \(.Name):\(.Destination)\(if .RW then "" else ":ro" end)"
    else
      empty
    end
')"

NETWORK_MODE="$(docker inspect "$CONTAINER_NAME" --format '{{.HostConfig.NetworkMode}}')"
NETWORK_ARGS=""
if [ "$NETWORK_MODE" != "default" ] && [ "$NETWORK_MODE" != "bridge" ]; then
  NETWORK_ARGS="--network $NETWORK_MODE"
fi

RESTART_NAME="$(docker inspect "$CONTAINER_NAME" --format '{{.HostConfig.RestartPolicy.Name}}')"
RESTART_MAX="$(docker inspect "$CONTAINER_NAME" --format '{{.HostConfig.RestartPolicy.MaximumRetryCount}}')"
RESTART_ARGS=""
if [ "$RESTART_NAME" != "no" ] && [ -n "$RESTART_NAME" ]; then
  if [ "$RESTART_NAME" = "on-failure" ] && [ "$RESTART_MAX" != "0" ]; then
    RESTART_ARGS="--restart ${RESTART_NAME}:${RESTART_MAX}"
  else
    RESTART_ARGS="--restart ${RESTART_NAME}"
  fi
fi

PRIVILEGED="$(docker inspect "$CONTAINER_NAME" --format '{{.HostConfig.Privileged}}')"
PRIVILEGED_ARGS=""
if [ "$PRIVILEGED" = "true" ]; then
  PRIVILEGED_ARGS="--privileged"
fi

EXTRA_HOST_ARGS="$(docker inspect "$CONTAINER_NAME" | jq -r '
  .[0].HostConfig.ExtraHosts[]? | "--add-host " + .
')"

WORKDIR="$(docker inspect "$CONTAINER_NAME" --format '{{.Config.WorkingDir}}')"
WORKDIR_ARGS=""
if [ -n "$WORKDIR" ]; then
  WORKDIR_ARGS="-w $WORKDIR"
fi

USER_NAME="$(docker inspect "$CONTAINER_NAME" --format '{{.Config.User}}')"
USER_ARGS=""
if [ -n "$USER_NAME" ]; then
  USER_ARGS="-u $USER_NAME"
fi

HOSTNAME_VALUE="$(docker inspect "$CONTAINER_NAME" --format '{{.Config.Hostname}}')"
HOSTNAME_ARGS=""
if [ -n "$HOSTNAME_VALUE" ]; then
  HOSTNAME_ARGS="--hostname $HOSTNAME_VALUE"
fi

ENTRYPOINT_JSON="$(docker inspect "$CONTAINER_NAME" | jq -c '.[0].Config.Entrypoint')"
ENTRYPOINT_ARGS=""
if [ "$ENTRYPOINT_JSON" != "null" ]; then
  ENTRYPOINT_VALUE="$(echo "$ENTRYPOINT_JSON" | jq -r 'join(" ")')"
  if [ -n "$ENTRYPOINT_VALUE" ]; then
    ENTRYPOINT_ARGS="--entrypoint \"$ENTRYPOINT_VALUE\""
  fi
fi

CMD_JSON="$(docker inspect "$CONTAINER_NAME" | jq -c '.[0].Config.Cmd')"
CMD_VALUE=""
if [ "$CMD_JSON" != "null" ]; then
  CMD_VALUE="$(echo "$CMD_JSON" | jq -r 'join(" ")')"
fi

echo "4. Stopping old container..."
docker stop "$CONTAINER_NAME"

echo "5. Renaming old container to backup..."
docker rename "$CONTAINER_NAME" "$BACKUP_NAME"

echo "6. Starting new container with the same original name..."

RUN_CMD="docker run -d \
  --name \"$CONTAINER_NAME\" \
  --env-file \"$ENV_FILE\" \
  $RESTART_ARGS \
  $NETWORK_ARGS \
  $PRIVILEGED_ARGS \
  $WORKDIR_ARGS \
  $USER_ARGS \
  $HOSTNAME_ARGS \
  $PORT_ARGS \
  $MOUNT_ARGS \
  $EXTRA_HOST_ARGS \
  $ENTRYPOINT_ARGS \
  \"$IMAGE\" \
  $CMD_VALUE"

echo "$RUN_CMD"
echo

if ! eval "$RUN_CMD"; then
  echo
  echo "Error: failed to start the new container."
  echo "Rolling back..."

  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker rename "$BACKUP_NAME" "$CONTAINER_NAME"
  docker start "$CONTAINER_NAME"

  echo "Rollback completed."
  exit 1
fi

echo
echo "7. Checking new container status..."
sleep 5

if ! docker ps --filter "name=^/${CONTAINER_NAME}$" --filter "status=running" | grep -q "$CONTAINER_NAME"; then
  echo
  echo "Error: new container is not running."
  echo "Rolling back..."

  docker logs --tail 100 "$CONTAINER_NAME" || true

  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker rename "$BACKUP_NAME" "$CONTAINER_NAME"
  docker start "$CONTAINER_NAME"

  echo "Rollback completed."
  exit 1
fi

echo
echo "8. Recent logs:"
docker logs --tail 50 "$CONTAINER_NAME" || true

echo
echo "========================================"
echo "Upgrade completed successfully."
echo "========================================"
echo "Container name : $CONTAINER_NAME"
echo "Image          : $IMAGE"
echo "Backup         : $BACKUP_NAME"
echo
echo "The new container is running with the same original name:"
echo "  $CONTAINER_NAME"
echo
echo "After confirming everything works, you can remove the backup container:"
echo "  docker rm $BACKUP_NAME"
echo
echo "Manual rollback:"
echo "  docker stop $CONTAINER_NAME"
echo "  docker rm $CONTAINER_NAME"
echo "  docker rename $BACKUP_NAME $CONTAINER_NAME"
echo "  docker start $CONTAINER_NAME"