#!/usr/bin/env bash
set -euo pipefail

TOTAL_STEPS=4
BAR_WIDTH=30
ANIM_PID=""

render_bar() {
  local pct="$1"
  local filled=$(( pct * BAR_WIDTH / 100 ))
  local empty=$(( BAR_WIDTH - filled ))
  local i

  printf '\r  ['
  for ((i = 0; i < filled; i++)); do printf '█'; done
  for ((i = 0; i < empty; i++)); do printf '░'; done
  printf '] %3d%%' "$pct" >&2
}

progress_finish() {
  if [ -t 2 ]; then
    printf '\n' >&2
  fi
}

stop_bar_animation() {
  if [ -n "$ANIM_PID" ]; then
    kill "$ANIM_PID" 2>/dev/null || true
    wait "$ANIM_PID" 2>/dev/null || true
    ANIM_PID=""
  fi
}

run_step() {
  local step="$1"
  local start_pct end_pct pct
  shift

  start_pct=$(( (step - 1) * 100 / TOTAL_STEPS ))
  end_pct=$(( step * 100 / TOTAL_STEPS ))

  if [ ! -t 2 ]; then
    if "$@"; then
      printf '[%s/%s]\n' "$step" "$TOTAL_STEPS"
      return 0
    fi
    return $?
  fi

  pct=$start_pct
  (
    while true; do
      render_bar "$pct"
      if [ "$pct" -lt "$end_pct" ]; then
        pct=$((pct + 1))
      fi
      sleep 0.08
    done
  ) &
  ANIM_PID=$!

  if "$@"; then
    local rc=0
  else
    local rc=$?
  fi

  stop_bar_animation
  render_bar "$end_pct"
  return "$rc"
}

fail() {
  stop_bar_animation
  progress_finish
  printf 'Error: %s\n' "$*" >&2
}

rollback_container() {
  fail "$1"
  printf 'Rolling back...\n'
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker rename "$BACKUP_NAME" "$CONTAINER_NAME"
  docker start "$CONTAINER_NAME" >/dev/null
  printf 'Rolled back to %s\n' "$CONTAINER_NAME"
}

say() {
  printf '%s\n' "$*"
}

# Strip tag or digest; keep registry host:port + repository path.
image_repo_name() {
  local ref="${1%%@*}"
  local tag_candidate="${ref##*:}"

  if [[ "$ref" == */* ]] && [[ "$ref" == *:* ]] && [[ "$tag_candidate" != */* ]]; then
    printf '%s' "${ref%:*}"
    return 0
  fi

  if [[ "$ref" != */* ]] && [[ "$ref" == *:* ]]; then
    printf '%s' "${ref%:*}"
    return 0
  fi

  printf '%s' "$ref"
}

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
  if command -v apt >/dev/null 2>&1; then
    apt update >/dev/null && apt install -y jq >/dev/null
  elif command -v yum >/dev/null 2>&1; then
    yum install -y jq >/dev/null
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y jq >/dev/null
  else
    fail "cannot install jq automatically; please install jq manually"
    exit 1
  fi
fi

if ! docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  echo "Error: container does not exist: $CONTAINER_NAME"
  exit 1
fi

CURRENT_IMAGE="$(docker inspect "$CONTAINER_NAME" --format '{{.Config.Image}}')"
IMAGE_REPO="$(image_repo_name "$CURRENT_IMAGE")"
TARGET_IMAGE="${IMAGE_REPO}:latest"
BACKUP_NAME="${CONTAINER_NAME}_backup_$(date +%Y%m%d_%H%M%S)"
TMP_DIR="/tmp/docker-upgrade-${CONTAINER_NAME}-$$"
ENV_FILE="$TMP_DIR/env.list"

read_container_config() {
  docker inspect "$CONTAINER_NAME" \
    --format='{{range .Config.Env}}{{println .}}{{end}}' > "$ENV_FILE"

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
}

replace_container() {
  docker stop "$CONTAINER_NAME" >/dev/null
  docker rename "$CONTAINER_NAME" "$BACKUP_NAME"

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
    \"$TARGET_IMAGE\" \
    $CMD_VALUE"

  eval "$RUN_CMD" >/dev/null
}

verify_container() {
  sleep 5
  docker ps --filter "name=^/${CONTAINER_NAME}$" --filter "status=running" --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"
}

mkdir -p "$TMP_DIR"

say "Updating $CONTAINER_NAME..."
if [ -t 2 ]; then
  render_bar 0
fi

run_step 1 docker pull -q "$TARGET_IMAGE"
run_step 2 read_container_config

if ! run_step 3 replace_container; then
  rollback_container "failed to start the new container"
  exit 1
fi

if ! run_step 4 verify_container; then
  docker logs --tail 30 "$CONTAINER_NAME" 2>&1 || true
  rollback_container "upgrade verification failed"
  exit 1
fi

progress_finish
say "Update complete."