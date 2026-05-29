# AntGain installer shared library (sourced, not executed directly)
# Override: ANTGAIN_INSTALL_BASE, ANTGAIN_R2_BASE_URL, ANTGAIN_INSTALLER_DIR

ANTGAIN_INSTALL_BASE="${ANTGAIN_INSTALL_BASE:-https://install.antgain.app}"
ANTGAIN_R2_BASE_URL="${ANTGAIN_R2_BASE_URL:-${R2_BASE_URL:-https://cdn.iprobe.io}}"
ANTGAIN_INSTALL_DIR="${ANTGAIN_INSTALL_DIR:-${INSTALL_DIR:-/usr/local/bin}}"
ANTGAIN_DATA_DIR="${ANTGAIN_DATA_DIR:-/var/lib/antgain}"
ANTGAIN_SERVICE_NAME="${ANTGAIN_SERVICE_NAME:-app.antgain.cli}"
ANTGAIN_AUTO_START="${ANTGAIN_AUTO_START:-true}"

ag_env_truthy() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

# Install service unit when API key is provided (unless skip).
ag_should_install_service() {
  [ "${ANTGAIN_SKIP_START:-}" != "1" ] && ! ag_env_truthy "${ANTGAIN_SKIP_START:-}"
}

# Start/restart service after unit is written (default on).
ag_should_start_service() {
  ag_env_truthy "${ANTGAIN_AUTO_START:-true}"
}

# Register boot-time start (default on when a service is installed).
ag_should_enable_on_boot() {
  ! ag_env_truthy "${ANTGAIN_NO_BOOT:-}"
}

ag_log() { echo "$@" >&2; }
ag_print_error() { echo -e "\033[0;31m❌ $*\033[0m" >&2; }
ag_print_success() { echo -e "\033[0;32m✅ $*\033[0m" >&2; }
ag_print_warning() { echo -e "\033[1;33m⚠️  $*\033[0m" >&2; }
ag_print_info() { echo "ℹ️  $*" >&2; }


ag_source_common() {
  return 0
}

ag_is_tty() {
  [ -t 0 ] && [ -t 1 ]
}

ag_confirm_default_no() {
  local prompt="$1"
  if ! ag_is_tty; then
    return 1
  fi
  local reply
  read -r -p "$prompt" reply </dev/tty || return 1
  case "$reply" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

ag_confirm_default_yes() {
  local prompt="$1"
  if ! ag_is_tty; then
    return 0
  fi
  local reply
  read -r -p "$prompt" reply </dev/tty || return 0
  case "$reply" in
    [nN]|[nN][oO]) return 1 ;;
    *) return 0 ;;
  esac
}

ag_run_root() {
  if [ "$EUID" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

ag_need_root() {
  if [ "$EUID" -ne 0 ]; then
    ag_print_error "Please run as root (use sudo)"
    exit 1
  fi
}

ag_normalize_version() {
  local v="$1"
  v="${v#v}"
  v="${v#V}"
  printf '%s' "$v"
}

ag_is_version_string() {
  # NOTE: in `case`, '.' is a wildcard — use bash regex instead.
  [[ "$1" =~ ^[vV]?[0-9]+(\.[0-9]+){1,3}([.+-].*)?$ ]]
}

ag_detect_platform() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"

  case "$os" in
    Linux*) OS_TYPE="linux" ;;
    Darwin*) OS_TYPE="darwin" ;;
    *)
      ag_print_error "Unsupported OS: $os"
      return 1
      ;;
  esac

  case "$arch" in
    x86_64|amd64) ARCH_TYPE="amd64" ;;
    aarch64|arm64) ARCH_TYPE="arm64" ;;
    armv7l|armv7|armhf|armv8l)
      if [ "$OS_TYPE" != "linux" ]; then
        ag_print_error "Unsupported architecture on $OS_TYPE: $arch"
        return 1
      fi
      ARCH_TYPE="armv7"
      ;;
    *)
      ag_print_error "Unsupported architecture: $arch"
      return 1
      ;;
  esac

  PLATFORM_KEY="${OS_TYPE}-${ARCH_TYPE}"
  export OS_TYPE ARCH_TYPE PLATFORM_KEY
}

# True when $0 is the shell or install script path (not a user version/api key).
ag_is_shell_or_script_path() {
  case "$1" in
    bash|/bin/bash|dash|/bin/dash|sh|/bin/sh|zsh|ksh|"")
      return 0
      ;;
    *.sh|*/install-cli*|*/cli.sh)
      return 0
      ;;
    /*)
      return 0
      ;;
  esac
  return 1
}

ag_apply_cli_arg() {
  local arg="$1"
  [ -z "$arg" ] && return 0
  if ag_is_version_string "$arg"; then
    TARGET_VERSION="$(ag_normalize_version "$arg")"
    return 0
  fi
  if [ -z "${ANTGAIN_API_KEY:-}" ]; then
    ANTGAIN_API_KEY="$arg"
  fi
}

ag_parse_cli_args() {
  # Sets: TARGET_VERSION, ANTGAIN_API_KEY
  TARGET_VERSION="${TARGET_VERSION:-${VERSION:-}}"
  ANTGAIN_API_KEY="${ANTGAIN_API_KEY:-}"

  # curl | bash -s 1.1.0  → version is in $0, not $@
  # curl | bash -s -- 1.1.0  → version is in $1 (preferred)
  if ! ag_is_shell_or_script_path "$0"; then
    ag_apply_cli_arg "$0"
  fi
  for arg in "$@"; do
    [ "$arg" = "--" ] && continue
    ag_apply_cli_arg "$arg"
  done

  export TARGET_VERSION ANTGAIN_API_KEY
}

ag_validate_cli_install_args() {
  if [ -n "${ANTGAIN_API_KEY:-}" ] && ag_is_version_string "$ANTGAIN_API_KEY"; then
    ag_print_error "The API key argument looks like a version number ($ANTGAIN_API_KEY)."
    ag_log "Your install script may be outdated, or arguments were parsed incorrectly."
    ag_log "Try:  VERSION=1.1.0 ANTGAIN_API_KEY=your-key curl -fsSL .../install-cli.sh | bash"
    ag_log "Or:   curl -fsSL .../install-cli.sh | bash -s -- 1.1.0 your-key"
    return 1
  fi
  if [ -n "${TARGET_VERSION:-}" ] && [ -z "${ANTGAIN_API_KEY:-}" ] && [ "$#" -ge 2 ]; then
    ag_print_warning "Second argument was not accepted as API key (check quoting)."
  fi
  return 0
}

ag_json_cli_version() {
  local json="$1"
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$json" | python3 -c '
import json, sys
data = json.loads(sys.stdin.read())
print(str(data.get("version", "")).lstrip("vV"))
'
    return 0
  fi
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -r '.version // empty' | sed 's/^[vV]//'
    return 0
  fi
  local version
  version="$(printf '%s' "$json" | tr -d '\n' | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  ag_normalize_version "$version"
}

ag_cli_release_download_url() {
  local platform_key="$1"
  local version="$2"
  local base="${ANTGAIN_R2_BASE_URL%/}"
  printf '%s/cli/releases/%s/antgain-%s.tar.gz' \
    "$base" \
    "$(ag_normalize_version "$version")" \
    "$platform_key"
}

ag_fetch_cli_release() {
  local platform_key="$1"
  local version="${2:-}"

  if [ -n "$version" ]; then
    CLI_VERSION="$(ag_normalize_version "$version")"
    CLI_ARCHIVE="antgain-${platform_key}.tar.gz"
    CLI_DOWNLOAD_URL="${ANTGAIN_R2_BASE_URL}/cli/releases/${CLI_VERSION}/${CLI_ARCHIVE}"
    CLI_CHECKSUM_URL="${CLI_DOWNLOAD_URL}.sha256"
    export CLI_VERSION CLI_DOWNLOAD_URL CLI_CHECKSUM_URL CLI_ARCHIVE
    return 0
  fi

  ag_print_info "Fetching latest CLI version..."
  local json
  json="$(curl -fsSL "${ANTGAIN_R2_BASE_URL}/cli/latest.json" 2>/dev/null || true)"
  if [ -z "$json" ]; then
    ag_print_error "Failed to fetch ${ANTGAIN_R2_BASE_URL}/cli/latest.json"
    echo "Specify a version: curl ... | bash -s 1.1.0" >&2
    return 1
  fi

  CLI_VERSION="$(ag_json_cli_version "$json")"

  if [ -z "$CLI_VERSION" ]; then
    ag_print_error "Could not resolve release for platform: $platform_key"
    ag_log "Pin a version explicitly (note the -- after -s):"
    ag_log "  curl -fsSL ${ANTGAIN_INSTALL_BASE:-https://install.antgain.app}/install-cli.sh | bash -s -- 1.1.0"
    ag_log "Or set: VERSION=1.1.0 curl ... | bash"
    return 1
  fi

  CLI_VERSION="$(ag_normalize_version "$CLI_VERSION")"
  CLI_ARCHIVE="antgain-${platform_key}.tar.gz"
  CLI_DOWNLOAD_URL="$(ag_cli_release_download_url "$platform_key" "$CLI_VERSION")"
  CLI_CHECKSUM_URL="${CLI_DOWNLOAD_URL}.sha256"
  export CLI_VERSION CLI_DOWNLOAD_URL CLI_CHECKSUM_URL CLI_ARCHIVE
}

ag_verify_sha256() {
  local file="$1"
  local checksum_url="$2"
  local sum_file expected actual

  [ -f "$file" ] || return 1
  [ -n "$checksum_url" ] || return 0

  sum_file="$(mktemp)"
  if ! curl -fsSL "$checksum_url" -o "$sum_file" 2>/dev/null; then
    ag_print_warning "Checksum file not found, skipping verification"
    rm -f "$sum_file"
    return 0
  fi

  expected="$(awk '{print $1}' "$sum_file" | head -1)"
  rm -f "$sum_file"
  [ -n "$expected" ] || return 0

  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$file" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  else
    ag_print_warning "sha256sum/shasum not found, skipping verification"
    return 0
  fi

  if [ "$expected" != "$actual" ]; then
    ag_print_error "SHA256 mismatch for $(basename "$file")"
    ag_print_error "Expected: $expected"
    ag_print_error "Actual:   $actual"
    return 1
  fi

  ag_print_success "SHA256 verified"
}

ag_find_binary_in_dir() {
  local dir="$1"
  local platform_key="$2"
  if [ -f "${dir}/antgain" ]; then
    printf '%s' "${dir}/antgain"
    return 0
  fi
  if [ -f "${dir}/antgain-${platform_key}/antgain" ]; then
    printf '%s' "${dir}/antgain-${platform_key}/antgain"
    return 0
  fi
  find "$dir" -maxdepth 3 -type f -name antgain 2>/dev/null | head -n 1
}

ag_install_cli_binary() {
  local platform_key="$1"
  local version="${2:-}"
  local install_dir="${3:-$ANTGAIN_INSTALL_DIR}"

  ag_fetch_cli_release "$platform_key" "$version" || return 1

  ag_print_info "Version: $CLI_VERSION"
  ag_print_info "Download: $CLI_DOWNLOAD_URL"

  local tmp archive_path binary
  tmp="$(mktemp -d)"
  archive_path="${tmp}/${CLI_ARCHIVE}"

  if ! curl -fL# -o "$archive_path" "$CLI_DOWNLOAD_URL"; then
    ag_print_error "Download failed"
    rm -rf "$tmp"
    return 1
  fi

  ag_verify_sha256 "$archive_path" "$CLI_CHECKSUM_URL" || {
    rm -rf "$tmp"
    return 1
  }

  tar xzf "$archive_path" -C "$tmp"
  binary="$(ag_find_binary_in_dir "$tmp" "$platform_key")"
  if [ -z "$binary" ] || [ ! -f "$binary" ]; then
    ag_print_error "Could not find antgain binary in archive"
    rm -rf "$tmp"
    return 1
  fi

  ag_macos_prepare_binary "$binary"

  ag_print_info "Installing to ${install_dir}/antgain ..."
  local install_path="${install_dir}/antgain"
  if [ -w "$install_dir" ]; then
    install -m 0755 "$binary" "$install_path"
  else
    ag_run_root install -m 0755 "$binary" "$install_path"
  fi

  ag_macos_prepare_binary "$install_path"

  rm -rf "$tmp"
  export INSTALLED_CLI_VERSION="$CLI_VERSION"
}

# Remove macOS quarantine on binaries downloaded from the internet.
ag_macos_prepare_binary() {
  local path="$1"
  [ "$(uname -s)" = "Darwin" ] || return 0
  [ -f "$path" ] || return 0
  if ! command -v xattr >/dev/null 2>&1; then
    return 0
  fi
  xattr -d com.apple.quarantine "$path" 2>/dev/null || true
  xattr -cr "$path" 2>/dev/null || true
}

ag_verify_cli_binary() {
  local bin err
  bin="$(command -v antgain 2>/dev/null || true)"
  if [ -z "$bin" ]; then
    ag_print_error "antgain not found in PATH (install dir: $ANTGAIN_INSTALL_DIR)"
    ag_print_info "Ensure ${ANTGAIN_INSTALL_DIR} is listed in your PATH"
    return 1
  fi

  ag_macos_prepare_binary "$bin"

  err="$("$bin" --version 2>&1)" || {
    ag_print_error "antgain is installed but failed to run: $bin"
    if [ -n "$err" ]; then
      ag_log "Error: $err"
    fi
    if [ "$(uname -s)" = "Darwin" ]; then
      ag_log "On macOS, allow the binary in System Settings → Privacy & Security,"
      ag_log "or run: xattr -d com.apple.quarantine $bin"
    else
      ag_log "Try: ldd $bin  (check for missing libraries / wrong architecture)"
    fi
    return 1
  }

  ag_print_success "Installed: $bin ($("$bin" --version 2>/dev/null | head -1))"
}

ag_ensure_linux_user() {
  if id antgain >/dev/null 2>&1; then
    return 0
  fi
  if command -v useradd >/dev/null 2>&1; then
    useradd --system --no-create-home --shell /usr/sbin/nologin antgain 2>/dev/null \
      || useradd -r -s /bin/false antgain 2>/dev/null \
      || true
  fi
}

ag_ensure_data_dir() {
  ag_run_root mkdir -p "${ANTGAIN_DATA_DIR}/logs"
  if id antgain >/dev/null 2>&1; then
    ag_run_root chown -R antgain:antgain "$ANTGAIN_DATA_DIR" 2>/dev/null || true
  fi
}

ANTGAIN_LINUX_ENV_FILE="${ANTGAIN_LINUX_ENV_FILE:-/etc/antgain/env}"
ANTGAIN_LINUX_START_SCRIPT="${ANTGAIN_LINUX_START_SCRIPT:-/usr/local/sbin/antgain-service}"

ag_has_systemd() {
  command -v systemctl >/dev/null 2>&1 || return 1
  if [ -d /run/systemd/system ] || [ -S /run/systemd/private ] 2>/dev/null; then
    return 0
  fi
  if [ -r /proc/1/comm ] && grep -q '^systemd$' /proc/1/comm 2>/dev/null; then
    return 0
  fi
  return 1
}

ag_has_openrc() {
  command -v rc-service >/dev/null 2>&1 && command -v rc-update >/dev/null 2>&1
}

ag_write_linux_env_file() {
  local api_key="$1"
  ag_run_root mkdir -p "$(dirname "$ANTGAIN_LINUX_ENV_FILE")"
  ag_run_root tee "$ANTGAIN_LINUX_ENV_FILE" >/dev/null <<EOF
ANTGAIN_API_KEY=${api_key}
LOG_LEVEL=${LOG_LEVEL:-info}
LOG_DIR=${ANTGAIN_DATA_DIR}/logs
EOF
  ag_run_root chmod 600 "$ANTGAIN_LINUX_ENV_FILE"
}

ag_install_linux_start_script() {
  local bin="$1"
  ag_run_root mkdir -p "$(dirname "$ANTGAIN_LINUX_START_SCRIPT")"
  ag_run_root tee "$ANTGAIN_LINUX_START_SCRIPT" >/dev/null <<EOF
#!/bin/sh
set -e
ENVFILE="${ANTGAIN_LINUX_ENV_FILE}"
BIN="${bin}"
[ -f "\$ENVFILE" ] && . "\$ENVFILE"
export ANTGAIN_API_KEY LOG_LEVEL LOG_DIR
case "\${1:-start}" in
  start)
    if [ -z "\${ANTGAIN_API_KEY:-}" ]; then
      echo "ANTGAIN_API_KEY missing in \$ENVFILE" >&2
      exit 1
    fi
    exec "\$BIN" run --daemon --api-key "\$ANTGAIN_API_KEY"
    ;;
  stop)
    exec "\$BIN" stop
    ;;
  status)
    exec "\$BIN" status
    ;;
  *)
    echo "Usage: \$0 {start|stop|status}" >&2
    exit 1
    ;;
esac
EOF
  ag_run_root chmod 755 "$ANTGAIN_LINUX_START_SCRIPT"
}

ag_print_linux_manual_start_hints() {
  ag_log ""
  ag_log "Manual start (no systemd on this device):"
  ag_log "  export ANTGAIN_API_KEY=your-key"
  ag_log "  antgain run --daemon"
  ag_log "Or use the installed helper:"
  ag_log "  sudo ${ANTGAIN_LINUX_START_SCRIPT} start"
  ag_log "  sudo ${ANTGAIN_LINUX_START_SCRIPT} stop"
  ag_log "Boot: enabled via /etc/init.d/antgain, OpenRC, or /etc/cron.d/antgain when possible"
}

ag_linux_sysv_boot_enabled() {
  local f
  for f in /etc/rc*.d/S*antgain*; do
    [ -e "$f" ] && return 0
  done
  if command -v chkconfig >/dev/null 2>&1; then
    chkconfig --list antgain 2>/dev/null | grep -qE ':on|启用' && return 0
  fi
  if command -v rc-update >/dev/null 2>&1; then
    rc-update show 2>/dev/null | grep -qE '[[:space:]]antgain[[:space:]]' && return 0
  fi
  return 1
}

ag_enable_sysv_init() {
  if command -v update-rc.d >/dev/null 2>&1; then
    update-rc.d antgain defaults 2>/dev/null || true
  elif command -v chkconfig >/dev/null 2>&1; then
    chkconfig --add antgain 2>/dev/null || true
    chkconfig antgain on 2>/dev/null || true
  elif command -v insserv >/dev/null 2>&1; then
    insserv antgain 2>/dev/null || true
  fi
  # BusyBox / Buildroot: symlink into runlevel dirs when tools are missing
  if ! ag_linux_sysv_boot_enabled && [ -x /etc/init.d/antgain ]; then
    local rl
    for rl in 2 3 4 5; do
      ag_run_root mkdir -p "/etc/rc${rl}.d"
      ag_run_root ln -sf ../init.d/antgain "/etc/rc${rl}.d/S99antgain" 2>/dev/null || true
    done
    for rl in 0 1 6; do
      ag_run_root mkdir -p "/etc/rc${rl}.d"
      ag_run_root ln -sf ../init.d/antgain "/etc/rc${rl}.d/K01antgain" 2>/dev/null || true
    done
  fi
}

ag_remove_linux_cron_reboot() {
  rm -f /etc/cron.d/antgain 2>/dev/null || true
  if [ -f /etc/crontabs/root ]; then
    sed -i '/antgain-service/d' /etc/crontabs/root 2>/dev/null \
      || sed -i '' '/antgain-service/d' /etc/crontabs/root 2>/dev/null \
      || true
    if command -v rc-service >/dev/null 2>&1; then
      rc-service crond restart 2>/dev/null || true
    fi
  fi
  if command -v crontab >/dev/null 2>&1; then
    crontab -l 2>/dev/null | grep -v 'antgain-service' | crontab - 2>/dev/null || true
  fi
}

ag_install_linux_cron_reboot() {
  local start_cmd="${ANTGAIN_LINUX_START_SCRIPT} start"
  if [ -d /etc/cron.d ]; then
    ag_run_root tee /etc/cron.d/antgain >/dev/null <<EOF
# AntGain CLI — start on boot (fallback when SysV/OpenRC is unavailable)
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
@reboot root ${start_cmd}
EOF
    ag_run_root chmod 644 /etc/cron.d/antgain
    return 0
  fi
  if [ -d /etc/crontabs ]; then
    local tab="/etc/crontabs/root"
    ag_run_root touch "$tab"
    if ! grep -q 'antgain-service' "$tab" 2>/dev/null; then
      ag_run_root sh -c "echo '@reboot ${start_cmd}' >> '$tab'"
    fi
    if command -v rc-service >/dev/null 2>&1; then
      rc-service crond restart 2>/dev/null || true
    fi
    return 0
  fi
  if command -v crontab >/dev/null 2>&1; then
    (crontab -l 2>/dev/null | grep -v 'antgain-service'; echo "@reboot ${start_cmd}") | crontab -
    return 0
  fi
  return 1
}

# Enable boot start for non-systemd Linux (SysV / OpenRC / cron fallback).
ag_enable_linux_boot_start() {
  local backend="${1:-helper}"

  if ! ag_should_enable_on_boot; then
    ag_print_info "Boot start skipped (ANTGAIN_NO_BOOT=1)"
    return 0
  fi

  case "$backend" in
    openrc)
      rc-update add antgain default 2>/dev/null || true
      ag_print_success "Boot start enabled (OpenRC: antgain default)"
      ;;
    sysv)
      ag_enable_sysv_init
      if ag_linux_sysv_boot_enabled; then
        ag_print_success "Boot start enabled (/etc/init.d/antgain)"
      else
        ag_print_warning "SysV enable uncertain; adding cron @reboot fallback"
        ag_install_linux_cron_reboot && ag_print_success "Boot start enabled (/etc/cron.d/antgain)"
      fi
      ;;
    helper)
      if ag_install_linux_cron_reboot; then
        ag_print_success "Boot start enabled (cron @reboot)"
      else
        ag_print_warning "Could not register boot start automatically"
        ag_print_linux_manual_start_hints
        return 1
      fi
      ;;
  esac
  return 0
}

ag_install_sysv_init_script() {
  local bin="$1"
  ag_run_root tee /etc/init.d/antgain >/dev/null <<EOF
#!/bin/sh
### BEGIN INIT INFO
# Provides:          antgain
# Required-Start:    \$network \$remote_fs
# Required-Stop:     \$network \$remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: AntGain CLI Node
### END INIT INFO

"${ANTGAIN_LINUX_START_SCRIPT}" "\$1"
EOF
  ag_run_root chmod 755 /etc/init.d/antgain
}

ag_install_openrc_init_script() {
  local bin="$1"
  ag_run_root tee /etc/init.d/antgain >/dev/null <<EOF
#!/sbin/openrc-run

name="antgain"
description="AntGain CLI Node"

depend() {
    need net
    after firewall
}

: "\${ANTGAIN_ENVFILE:=${ANTGAIN_LINUX_ENV_FILE}}"
[ -f "\$ANTGAIN_ENVFILE" ] && . "\$ANTGAIN_ENVFILE"
export ANTGAIN_API_KEY LOG_LEVEL LOG_DIR

command="${bin}"
command_args="run --daemon --api-key \${ANTGAIN_API_KEY}"
command_background="yes"
pidfile="/run/antgain.pid"
EOF
  ag_run_root chmod 755 /etc/init.d/antgain
}

ag_install_linux_fallback_service() {
  local api_key="$1"
  local bin="${2:-$(command -v antgain)}"
  local skip_confirm="${3:-false}"

  ag_need_root
  ag_ensure_data_dir

  if [ "$skip_confirm" != "true" ] && [ "${ANTGAIN_SKIP_CONFIRM:-}" != "1" ]; then
    ag_log ""
    ag_log "systemd is not available — using SysV/OpenRC or a startup helper."
    ag_log "Env file: ${ANTGAIN_LINUX_ENV_FILE}"
    ag_log ""
    if ! ag_confirm_default_no "Continue? [y/N] "; then
      ag_print_warning "Service installation cancelled"
      return 1
    fi
  fi

  ag_write_linux_env_file "$api_key"
  ag_install_linux_start_script "$bin"

  if ag_has_openrc && [ -d /etc/init.d ]; then
    ag_install_openrc_init_script "$bin"
    ag_enable_linux_boot_start openrc
    if ag_should_start_service; then
      if rc-service antgain start 2>/dev/null; then
        ag_print_success "OpenRC service started (antgain)"
        return 0
      fi
      ag_print_warning "OpenRC start failed; trying helper script"
      "${ANTGAIN_LINUX_START_SCRIPT}" start && ag_print_success "Node started via ${ANTGAIN_LINUX_START_SCRIPT}"
      return 0
    fi
    ag_print_success "OpenRC service installed (starts on next boot)"
    return 0
  fi

  if [ -d /etc/init.d ]; then
    ag_install_sysv_init_script "$bin"
    ag_enable_linux_boot_start sysv
    if ag_should_start_service; then
      if /etc/init.d/antgain start 2>/dev/null; then
        ag_print_success "SysV service started (/etc/init.d/antgain)"
        return 0
      fi
      if "${ANTGAIN_LINUX_START_SCRIPT}" start 2>/dev/null; then
        ag_print_success "Node started via ${ANTGAIN_LINUX_START_SCRIPT}"
        return 0
      fi
      ag_print_warning "Could not start now; will retry on boot"
      return 0
    fi
    ag_print_success "SysV init installed (starts on next boot)"
    return 0
  fi

  ag_enable_linux_boot_start helper
  ag_print_success "Startup helper installed: ${ANTGAIN_LINUX_START_SCRIPT}"
  if ag_should_start_service; then
    if "${ANTGAIN_LINUX_START_SCRIPT}" start 2>/dev/null; then
      ag_print_success "Node started in background"
      return 0
    fi
    ag_print_warning "Could not start now; will retry on boot"
    return 0
  fi
  return 0
}

ag_remove_linux_fallback_service() {
  /etc/init.d/antgain stop 2>/dev/null || true
  if ag_has_openrc; then
    rc-service antgain stop 2>/dev/null || true
    rc-update del antgain 2>/dev/null || true
  fi
  if command -v update-rc.d >/dev/null 2>&1; then
    update-rc.d -f antgain remove 2>/dev/null || true
  elif command -v chkconfig >/dev/null 2>&1; then
    chkconfig --del antgain 2>/dev/null || true
  fi
  ag_remove_linux_cron_reboot
  rm -f /etc/init.d/antgain
  rm -f "$ANTGAIN_LINUX_START_SCRIPT"
  rm -f "$ANTGAIN_LINUX_ENV_FILE"
  rmdir /etc/antgain 2>/dev/null || true
}

ag_install_systemd_service() {
  local api_key="$1"
  local bin="${2:-$(command -v antgain)}"
  local skip_confirm="${3:-false}"

  ag_need_root
  ag_ensure_linux_user
  ag_ensure_data_dir

  if [ "$skip_confirm" != "true" ] && [ "${ANTGAIN_SKIP_CONFIRM:-}" != "1" ]; then
    ag_log ""
    ag_log "This installs a systemd service (auto-start on boot, restart on failure)."
    ag_log "Data directory: ${ANTGAIN_DATA_DIR}"
    ag_log ""
    if ! ag_confirm_default_no "Continue? [y/N] "; then
      ag_print_warning "Service installation cancelled"
      return 1
    fi
  fi

  cat > /etc/systemd/system/antgain.service <<EOF
[Unit]
Description=AntGain CLI Node
Documentation=https://docs.antgain.app
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=antgain
Group=antgain
Environment=ANTGAIN_API_KEY=${api_key}
Environment=LOG_LEVEL=${LOG_LEVEL:-info}
Environment=LOG_DIR=${ANTGAIN_DATA_DIR}/logs
ExecStart=${bin}
Restart=on-failure
RestartSec=30
StartLimitInterval=300
StartLimitBurst=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=${ANTGAIN_DATA_DIR} /tmp
StateDirectory=antgain
StandardOutput=journal
StandardError=journal
SyslogIdentifier=antgain

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  if ag_should_enable_on_boot; then
    systemctl enable antgain.service
    ag_print_success "Boot start enabled (systemd: antgain.service)"
  else
    systemctl disable antgain.service 2>/dev/null || true
  fi

  if ag_should_start_service; then
    systemctl restart antgain.service
    sleep 2
    if systemctl is-active --quiet antgain.service; then
      ag_print_success "systemd service is running"
      return 0
    fi
    ag_print_warning "Service installed but not active yet (enabled on boot)"
    ag_print_info "Check: journalctl -u antgain -n 50 --no-pager"
    return 1
  fi

  ag_print_success "systemd service installed (starts on next boot)"
  ag_print_info "Start now: sudo systemctl start antgain.service"
  return 0
}

ag_install_launchd_service() {
  local api_key="$1"
  local bin="${2:-$(command -v antgain)}"
  local skip_confirm="${3:-false}"
  local plist="/Library/LaunchDaemons/${ANTGAIN_SERVICE_NAME}.plist"

  ag_need_root

  if [ "$skip_confirm" != "true" ] && [ "${ANTGAIN_SKIP_CONFIRM:-}" != "1" ]; then
    ag_log ""
    ag_log "This installs a LaunchDaemon (auto-start on boot)."
    ag_log ""
    if ! ag_confirm_default_no "Continue? [y/N] "; then
      ag_print_warning "Service installation cancelled"
      return 1
    fi
  fi

  cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${ANTGAIN_SERVICE_NAME}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${bin}</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>ANTGAIN_API_KEY</key>
    <string>${api_key}</string>
    <key>LOG_LEVEL</key>
    <string>${LOG_LEVEL:-info}</string>
    <key>LOG_DIR</key>
    <string>${ANTGAIN_DATA_DIR}/logs</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>
  <key>ThrottleInterval</key>
  <integer>60</integer>
  <key>StandardOutPath</key>
  <string>/var/log/antgain.log</string>
  <key>StandardErrorPath</key>
  <string>/var/log/antgain.error.log</string>
</dict>
</plist>
EOF

  chown root:wheel "$plist"
  chmod 644 "$plist"
  touch /var/log/antgain.log /var/log/antgain.error.log
  chmod 644 /var/log/antgain.log /var/log/antgain.error.log

  launchctl bootout "system/${ANTGAIN_SERVICE_NAME}" 2>/dev/null || true
  launchctl unload "$plist" 2>/dev/null || true
  sleep 1

  # Always register for boot (RunAtLoad + KeepAlive in plist).
  if ag_should_enable_on_boot; then
    if launchctl bootstrap system "$plist" 2>/dev/null; then
      launchctl enable "system/${ANTGAIN_SERVICE_NAME}" 2>/dev/null || true
    else
      launchctl load -w "$plist"
    fi
    ag_print_success "Boot start enabled (launchd: ${ANTGAIN_SERVICE_NAME})"
  fi

  if ag_should_start_service; then
    launchctl kickstart -k "system/${ANTGAIN_SERVICE_NAME}" 2>/dev/null || true
    sleep 2
    if launchctl print "system/${ANTGAIN_SERVICE_NAME}" >/dev/null 2>&1 \
      || launchctl list 2>/dev/null | grep -q "${ANTGAIN_SERVICE_NAME}"; then
      ag_print_success "LaunchDaemon running"
      return 0
    fi
    ag_print_warning "LaunchDaemon may not be running yet (enabled on boot)"
    ag_print_info "Check: tail -f /var/log/antgain.error.log"
    return 1
  fi

  ag_print_success "LaunchDaemon installed (starts on next boot)"
  ag_print_info "Start now: sudo launchctl kickstart -k system/${ANTGAIN_SERVICE_NAME}"
  return 0
}

ag_install_and_start_service() {
  local api_key="$1"
  local skip_confirm="${2:-false}"

  if [ -z "$api_key" ]; then
    ag_print_error "API key is required to start the service"
    return 1
  fi

  if ! command -v antgain >/dev/null 2>&1; then
    ag_print_error "antgain binary not found"
    return 1
  fi

  local os
  os="$(uname -s)"
  case "$os" in
    Linux*)
      if ag_has_systemd; then
        ag_install_systemd_service "$api_key" "$(command -v antgain)" "$skip_confirm"
      else
        ag_print_info "systemd not detected — using SysV/OpenRC/startup helper"
        ag_install_linux_fallback_service "$api_key" "$(command -v antgain)" "$skip_confirm"
      fi
      ;;
    Darwin*)
      ag_install_launchd_service "$api_key" "$(command -v antgain)" "$skip_confirm"
      ;;
    *)
      ag_print_error "Unsupported OS for service: $os"
      return 1
      ;;
  esac
}

ag_start_service_if_installed() {
  local os
  os="$(uname -s)"
  case "$os" in
    Linux*)
      if systemctl list-unit-files antgain.service >/dev/null 2>&1; then
        ag_run_root systemctl restart antgain.service
        ag_print_success "Restarted antgain.service"
      fi
      ;;
    Darwin*)
      local plist="/Library/LaunchDaemons/${ANTGAIN_SERVICE_NAME}.plist"
      if [ -f "$plist" ]; then
        ag_run_root launchctl kickstart -k "system/${ANTGAIN_SERVICE_NAME}" 2>/dev/null \
          || ag_run_root launchctl load -w "$plist"
        ag_print_success "Started LaunchDaemon"
      fi
      ;;
  esac
}

ag_print_service_status() {
  local os
  os="$(uname -s)"
  ag_log ""
  ag_log "Service status"
  ag_log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  case "$os" in
    Linux*)
      if ag_has_systemd; then
        systemctl is-active antgain.service 2>/dev/null && ag_log "  systemd: running" || ag_log "  systemd: not running"
        systemctl is-enabled antgain.service 2>/dev/null || true
      elif [ -f /etc/init.d/antgain ]; then
        if [ -x "${ANTGAIN_LINUX_START_SCRIPT}" ] && pgrep -f '[a]ntgain' >/dev/null 2>&1; then
          ag_log "  init: running (pgrep antgain)"
        else
          ag_log "  init: not running (/etc/init.d/antgain)"
        fi
        ag_log "  helper: ${ANTGAIN_LINUX_START_SCRIPT}"
      elif [ -x "${ANTGAIN_LINUX_START_SCRIPT}" ]; then
        ag_log "  helper: ${ANTGAIN_LINUX_START_SCRIPT} (no init.d)"
      fi
      ;;
    Darwin*)
      if launchctl print "system/${ANTGAIN_SERVICE_NAME}" >/dev/null 2>&1; then
        ag_log "  launchd: loaded (${ANTGAIN_SERVICE_NAME})"
      else
        ag_log "  launchd: not loaded"
      fi
      ;;
  esac
  ag_log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

ag_remove_systemd_service() {
  systemctl stop antgain.service 2>/dev/null || true
  systemctl disable antgain.service 2>/dev/null || true
  rm -f /etc/systemd/system/antgain.service
  systemctl daemon-reload 2>/dev/null || true
}

ag_remove_launchd_service() {
  local plist="/Library/LaunchDaemons/${ANTGAIN_SERVICE_NAME}.plist"
  launchctl bootout "system/${ANTGAIN_SERVICE_NAME}" 2>/dev/null || true
  launchctl unload "$plist" 2>/dev/null || true
  rm -f "$plist"
  rm -f /var/log/antgain.log /var/log/antgain.error.log
}

ag_fetch_desktop_deb_url() {
  local version="${1:-}"
  local arch_type="${2:-amd64}"

  if [ "$arch_type" != "amd64" ]; then
    ag_print_error "Desktop one-line installer supports linux x86_64 (amd64) only"
    return 1
  fi

  if [ -n "$version" ]; then
    DESKTOP_VERSION="$(ag_normalize_version "$version")"
    DESKTOP_DEB_URL="${ANTGAIN_R2_BASE_URL}/releases/${DESKTOP_VERSION}/AntGain_${DESKTOP_VERSION}_linux-x86_64.deb"
    export DESKTOP_VERSION DESKTOP_DEB_URL
    return 0
  fi

  local json
  json="$(curl -fsSL "${ANTGAIN_R2_BASE_URL}/latest.json" 2>/dev/null || true)"
  if [ -z "$json" ]; then
    ag_print_error "Failed to fetch ${ANTGAIN_R2_BASE_URL}/latest.json"
    return 1
  fi

  if command -v python3 >/dev/null 2>&1; then
    DESKTOP_VERSION="$(printf '%s' "$json" | python3 -c '
import json, sys
data = json.loads(sys.stdin.read())
print(str(data.get("version", "")).lstrip("vV"))
')"
    DESKTOP_DEB_URL="$(printf '%s' "$json" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
url = (
    data.get('downloads', {})
    .get('linux-x86_64', {})
    .get('files', {})
    .get('deb', {})
    .get('url', '')
)
if not url:
    v = str(data.get('version', '')).lstrip('vV')
    base = sys.argv[1]
    if v and base:
        url = f\"{base}/releases/{v}/AntGain_{v}_linux-x86_64.deb\"
print(url)
" "$ANTGAIN_R2_BASE_URL")"
  else
    DESKTOP_VERSION="$(printf '%s' "$json" | tr -d '\n' | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
    DESKTOP_VERSION="$(ag_normalize_version "$DESKTOP_VERSION")"
    DESKTOP_DEB_URL="${ANTGAIN_R2_BASE_URL}/releases/${DESKTOP_VERSION}/AntGain_${DESKTOP_VERSION}_linux-x86_64.deb"
  fi

  if [ -z "$DESKTOP_VERSION" ] || [ -z "$DESKTOP_DEB_URL" ]; then
    ag_print_error "Could not resolve desktop .deb URL"
    return 1
  fi
  export DESKTOP_VERSION DESKTOP_DEB_URL
}
