#!/usr/bin/env bash
set -euo pipefail
umask 077

CONTAINER_NAME="${1:-}"
[ -n "$CONTAINER_NAME" ] || { echo 'Usage: docker-update.sh CONTAINER_NAME' >&2; exit 1; }
command -v docker >/dev/null 2>&1 || { echo 'Docker is not installed' >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo 'Install jq before running this script' >&2; exit 1; }

TMP_DIR="$(mktemp -d)"
BACKUP_NAME="${CONTAINER_NAME}_backup_$(date +%Y%m%d_%H%M%S)_$$"
BACKUP_CREATED=false
NEW_CREATED=false
COMPLETED=false
WAS_RUNNING=false
ORIGINAL_STOPPED=false
cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  if [ "$COMPLETED" != true ] && [ "$BACKUP_CREATED" = true ]; then
    echo 'Upgrade did not complete; restoring the previous container.' >&2
    if [ "$NEW_CREATED" = true ]; then
      docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    fi
    if docker rename "$BACKUP_NAME" "$CONTAINER_NAME"; then
      if [ "$WAS_RUNNING" = true ]; then
        docker start "$CONTAINER_NAME" >/dev/null || echo 'Restored container could not start; check Docker logs.' >&2
      fi
    else
      echo "Restore failed. Previous container is retained as $BACKUP_NAME." >&2
    fi
  fi
  if [ "$COMPLETED" != true ] && [ "$BACKUP_CREATED" != true ] && [ "$ORIGINAL_STOPPED" = true ]; then
    docker start "$CONTAINER_NAME" >/dev/null || echo 'Could not restart the original container.' >&2
  fi
  rm -rf "$TMP_DIR"
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

CONFIG="$TMP_DIR/container.json"
docker inspect "$CONTAINER_NAME" >"$CONFIG"
if [ "$(jq -r '.[0].Config.Labels["com.docker.compose.project"] // empty' "$CONFIG")" != "" ]; then
  echo 'This container is managed by Compose. Use docker compose pull && docker compose up -d.' >&2
  exit 1
fi
CURRENT_IMAGE="$(jq -r '.[0].Config.Image' "$CONFIG")"
# Containers created from an image ID still need a repository for the next update.
docker image inspect "$(jq -r '.[0].Image' "$CONFIG")" >"$TMP_DIR/image.json"
if [[ "$CURRENT_IMAGE" == sha256:* ]]; then
  CURRENT_IMAGE="$(jq -r '.[0].RepoTags // [] | map(select(. != "<none>:<none>")) | .[0] // empty' "$TMP_DIR/image.json")"
  [ -n "$CURRENT_IMAGE" ] || CURRENT_IMAGE="$(jq -r '.[0].RepoDigests[0] // empty' "$TMP_DIR/image.json")"
  [ -n "$CURRENT_IMAGE" ] || { echo 'Cannot resolve the image repository; old container preserved.' >&2; exit 1; }
fi
IMAGE_REPO="${CURRENT_IMAGE%%@*}"
if [[ "${IMAGE_REPO##*/}" == *:* ]]; then IMAGE_REPO="${IMAGE_REPO%:*}"; fi
TARGET_IMAGE="${IMAGE_REPO}:latest"
if [ "$(jq -r '.[0].State.Running' "$CONFIG")" = true ]; then WAS_RUNNING=true; fi
# Compare image defaults so a newer image can supply its own entrypoint/command.
echo "Pulling $TARGET_IMAGE..."
docker pull "$TARGET_IMAGE"
# Recreate the image we just pulled, even if :latest moves during this operation.
docker image inspect "$TARGET_IMAGE" >"$TMP_DIR/target-image.json"
TARGET_ID="$(jq -r '.[0].Id' "$TMP_DIR/target-image.json")"
TARGET_REF="$(jq -r --arg repo "$IMAGE_REPO" '
  def normalized: sub("^(docker.io|index.docker.io)/"; "");
  [.[0].RepoDigests[]? | select((split("@")[0] | normalized) == ($repo | normalized))] | .[0] // empty
' "$TMP_DIR/target-image.json")"
TARGET_REF="${TARGET_REF:-$TARGET_IMAGE}"

jq -r '.[0].Config.Env[]?' "$CONFIG" >"$TMP_DIR/env.list"
chmod 600 "$TMP_DIR/env.list"
RUN_ARGS=(create --name "$CONTAINER_NAME" --env-file "$TMP_DIR/env.list")
RESTART_NAME="$(jq -r '.[0].HostConfig.RestartPolicy.Name // "no"' "$CONFIG")"
RESTART_MAX="$(jq -r '.[0].HostConfig.RestartPolicy.MaximumRetryCount // 0' "$CONFIG")"
if [ "$RESTART_NAME" = on-failure ] && [ "$RESTART_MAX" != 0 ]; then
  RUN_ARGS+=(--restart "on-failure:$RESTART_MAX")
else
  RUN_ARGS+=(--restart "$RESTART_NAME")
fi
NETWORK="$(jq -r '.[0].HostConfig.NetworkMode' "$CONFIG")"
if [ "$NETWORK" != default ] && [ "$NETWORK" != bridge ]; then RUN_ARGS+=(--network "$NETWORK"); fi
[ "$(jq -r '.[0].HostConfig.Privileged' "$CONFIG")" != true ] || RUN_ARGS+=(--privileged)
for property in WorkingDir User Hostname; do
  value="$(jq -r --arg key "$property" '.[0].Config[$key] // empty' "$CONFIG")"
  [ -n "$value" ] || continue
  case "$property" in
    WorkingDir) RUN_ARGS+=(--workdir "$value") ;;
    User) RUN_ARGS+=(--user "$value") ;;
    Hostname) RUN_ARGS+=(--hostname "$value") ;;
  esac
done
while IFS= read -r port; do
  [ -n "$port" ] && RUN_ARGS+=(-p "$port")
done < <(jq -r '.[0].HostConfig.PortBindings // {} | to_entries[]? | .key as $port | .value[]? |
  if .HostIp == "" or .HostIp == "0.0.0.0" then "\(.HostPort):\($port)"
  elif (.HostIp | contains(":")) then "[\(.HostIp)]:\(.HostPort):\($port)"
  else "\(.HostIp):\(.HostPort):\($port)" end' "$CONFIG")
while IFS= read -r mount; do
  [ -n "$mount" ] && RUN_ARGS+=(-v "$mount")
done < <(jq -r '.[0].Mounts[]? | select(.Type == "bind" or .Type == "volume") |
  "\(if .Type == "bind" then .Source else .Name end):\(.Destination)\(if .RW then "" else ":ro" end)"' "$CONFIG")
while IFS= read -r tmpfs; do RUN_ARGS+=(--tmpfs "$tmpfs"); done < <(jq -r '.[0].HostConfig.Tmpfs // {} | to_entries[]? | "\(.key):\(.value)"' "$CONFIG")
while IFS= read -r host; do RUN_ARGS+=(--add-host "$host"); done < <(jq -r '.[0].HostConfig.ExtraHosts[]?' "$CONFIG")
while IFS= read -r label; do RUN_ARGS+=(--label "$label"); done < <(jq -r '.[0].Config.Labels // {} | to_entries[]? | "\(.key)=\(.value)"' "$CONFIG")

# Retain an explicitly configured probe. With no override the new image supplies it.
TEST_TYPE="$(jq -r '.[0].Config.Healthcheck.Test[0] // empty' "$CONFIG")"
case "$TEST_TYPE" in
  CMD) HEALTH_CMD="$(jq -r '.[0].Config.Healthcheck.Test[1:] | @sh' "$CONFIG")"; RUN_ARGS+=(--health-cmd "$HEALTH_CMD") ;;
  CMD-SHELL) RUN_ARGS+=(--health-cmd "$(jq -r '.[0].Config.Healthcheck.Test[1]' "$CONFIG")") ;;
  NONE) echo 'Health checks are disabled. Enable antgain health before upgrading.' >&2; exit 1 ;;
esac
for property in Interval Timeout StartPeriod; do
  value="$(jq -r --arg key "$property" '.[0].Config.Healthcheck[$key] // 0' "$CONFIG")"
  # Match the client startup grace period, including older 15s configurations.
  if [ "$property" = StartPeriod ] && [ "$value" -lt 120000000000 ]; then value=120000000000; fi
  [ "$value" -gt 0 ] || continue
  case "$property" in
    Interval) RUN_ARGS+=(--health-interval "${value}ns") ;;
    Timeout) RUN_ARGS+=(--health-timeout "${value}ns") ;;
    StartPeriod) RUN_ARGS+=(--health-start-period "${value}ns") ;;
  esac
done
retries="$(jq -r '.[0].Config.Healthcheck.Retries // 0' "$CONFIG")"
[ "$retries" -le 0 ] || RUN_ARGS+=(--health-retries "$retries")

COMMAND_ARGS=()
ENTRYPOINT="$(jq -c '.[0].Config.Entrypoint' "$CONFIG")"
BASE_ENTRYPOINT="$(jq -c '.[0].Config.Entrypoint' "$TMP_DIR/image.json")"
CMD="$(jq -c '.[0].Config.Cmd' "$CONFIG")"
BASE_CMD="$(jq -c '.[0].Config.Cmd' "$TMP_DIR/image.json")"
if [ "$ENTRYPOINT" != "$BASE_ENTRYPOINT" ]; then
  RUN_ARGS+=(--entrypoint "$(jq -r '.[0].Config.Entrypoint[0] // ""' "$CONFIG")")
  while IFS= read -r -d '' arg; do COMMAND_ARGS+=("$arg"); done < <(jq -j '.[0].Config.Entrypoint[1:][]? | ., "\u0000"' "$CONFIG")
fi
if [ "$CMD" != "$BASE_CMD" ] || [ "$ENTRYPOINT" != "$BASE_ENTRYPOINT" ]; then
  while IFS= read -r -d '' arg; do COMMAND_ARGS+=("$arg"); done < <(jq -j '.[0].Config.Cmd[]? | ., "\u0000"' "$CONFIG")
fi

HEALTH_TIMEOUT="${ANTGAIN_UPDATE_HEALTH_TIMEOUT:-300}"
[[ "$HEALTH_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || { echo 'Health timeout must be positive seconds' >&2; exit 1; }
echo 'Replacing container...'
if [ "$WAS_RUNNING" = true ]; then
  docker stop "$CONTAINER_NAME" >/dev/null
  ORIGINAL_STOPPED=true
fi
docker rename "$CONTAINER_NAME" "$BACKUP_NAME"
BACKUP_CREATED=true
# Create separately so a failed start still has an unambiguous rollback target.
# The conditional expansion also works for empty arrays in macOS Bash 3.2.
docker "${RUN_ARGS[@]}" "$TARGET_REF" ${COMMAND_ARGS[@]+"${COMMAND_ARGS[@]}"} >/dev/null
NEW_CREATED=true
if [ "$(docker inspect "$CONTAINER_NAME" --format '{{.Image}}')" != "$TARGET_ID" ]; then
  echo 'Image changed during recreation; restoring the old container.' >&2
  exit 1
fi
docker start "$CONTAINER_NAME" >/dev/null

echo 'Waiting for AntGain to become healthy...'
DEADLINE=$((SECONDS + HEALTH_TIMEOUT))
while [ "$SECONDS" -lt "$DEADLINE" ]; do
  STATE="$(docker inspect "$CONTAINER_NAME" --format '{{.State.Status}}')"
  HEALTH="$(docker inspect "$CONTAINER_NAME" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}')"
  if [ "$STATE" != running ] || [ "$HEALTH" = missing ]; then
    echo "Container cannot pass verification (state=$STATE, health=$HEALTH)." >&2
    exit 1
  fi
  if [ "$HEALTH" = healthy ]; then
    # A previously stopped container must stay stopped after an image upgrade.
    [ "$WAS_RUNNING" = true ] || docker stop "$CONTAINER_NAME" >/dev/null
    COMPLETED=true
    if ! docker rm "$BACKUP_NAME" >/dev/null; then
      echo "Upgrade succeeded; remove leftover backup $BACKUP_NAME manually." >&2
    fi
    echo 'Update complete.'
    exit 0
  fi
  sleep 5
done
echo 'Health verification timed out; keeping the previous container.' >&2
exit 1
