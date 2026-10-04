#!/bin/bash
set -euo pipefail
# Removes the CLI and its startup registration. Data is preserved unless explicitly purged.
_ag_installer_root="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [ -f "${_ag_installer_root}/lib/common.sh" ]; then
  . "${_ag_installer_root}/lib/common.sh"
else
  temporary="$(mktemp)"
  trap 'rm -f "$temporary"' EXIT
  curl --connect-timeout 15 --max-time 60 -fsSL "${ANTGAIN_INSTALL_BASE:-https://install.antgain.app}/lib/common.sh" -o "$temporary"
  . "$temporary"
  rm -f "$temporary"
  trap - EXIT
fi

purge_requested() {
  ag_env_truthy "${ANTGAIN_UNINSTALL_PURGE:-}" && return 0
  [ "${ANTGAIN_UNINSTALL_YES:-}" != 1 ] && ag_confirm_default_no "Delete saved credentials, device identity, and logs? [y/N] "
}
remove_cli_files() {
  local dir="$1"
  [ -n "$dir" ] && [ "$dir" != / ] || return 1
  rm -f "${dir}/antgain" "${dir}/antgain.stable" "${dir}/antgain.old" \
    "${dir}/.antgain."*.tmp "${dir}/.antgain.install."*
}
remove_data() {
  local dir="$1"
  case "$dir" in ''|/|/home|/Users|/var|/var/lib|/tmp|/usr|/usr/local|"${HOME}")
    ag_print_error "Refusing to delete a parent directory: $dir"; return 1 ;;
  esac
  [ ! -d "$dir" ] || rm -rf "$dir"
}

ag_log 'AntGain CLI Uninstaller'
# User services must be removed in the owning user's session, before escalation.
if [ "${ANTGAIN_UNINSTALL_SCOPE:-}" != system ]; then
  user_home="$HOME"
  user_uid="$UID"
  user_name=""
  if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
    user_name="$SUDO_USER"
    user_uid="$(id -u "$user_name")"
    if command -v getent >/dev/null 2>&1; then
      user_home="$(getent passwd "$user_name" | cut -d: -f6)"
    else
      user_home="$(dscl . -read "/Users/$user_name" NFSHomeDirectory | sed 's/^NFSHomeDirectory: //')"
    fi
  fi
  user_run() {
    if [ -n "$user_name" ]; then
      sudo -u "$user_name" env HOME="$user_home" XDG_RUNTIME_DIR="/run/user/$user_uid" "$@"
    else
      "$@"
    fi
  }
  user_unit="${XDG_CONFIG_HOME:-${user_home}/.config}/systemd/user/antgain.service"
  if [ -f "$user_unit" ]; then
    user_run systemctl --user stop antgain.service || true
    user_run systemctl --user disable antgain.service || true
    rm -f "$user_unit"
    user_run systemctl --user daemon-reload || true
  fi
  if command -v crontab >/dev/null 2>&1; then
    tab="$(mktemp)"
    if user_run crontab -l >"$tab" 2>/dev/null && grep -Eq 'antgain-installer @reboot|ANTGAIN_API_KEY=.*antgain.*run --daemon' "$tab"; then
      sed '/antgain-installer @reboot/d; /ANTGAIN_API_KEY=.*antgain.*run --daemon/d' "$tab" >"${tab}.clean"
      user_run crontab - <"${tab}.clean"
      rm -f "${tab}.clean"
    fi
    rm -f "$tab"
  fi
  if [ -x "${user_home}/.antgain/service.sh" ]; then
    user_run "${user_home}/.antgain/service.sh" stop || true
  fi
  if [ -x "${user_home}/.local/bin/antgain" ]; then
    user_run env ANTGAIN_DATA_DIR="${user_home}/.antgain" "${user_home}/.local/bin/antgain" stop || true
    remove_cli_files "${user_home}/.local/bin"
  fi
  if [ -n "${ANTGAIN_INSTALL_DIR:-}" ] && [[ "$ANTGAIN_INSTALL_DIR" == "$user_home/"* ]]; then
    if [ -x "${ANTGAIN_INSTALL_DIR}/antgain" ]; then
      user_run env ANTGAIN_DATA_DIR="${user_home}/.antgain" "${ANTGAIN_INSTALL_DIR}/antgain" stop || true
    fi
    remove_cli_files "$ANTGAIN_INSTALL_DIR"
  fi
  rm -f "${user_home}/.antgain/service.sh" "${user_home}/.antgain/service.env" "${user_home}/.antgain/env"
  if [ -d "${user_home}/.antgain" ] && purge_requested; then
    remove_data "${user_home}/.antgain"
  fi
fi

system_install=false
if [ -e "${ANTGAIN_INSTALL_DIR}/antgain" ] || [ -L "${ANTGAIN_INSTALL_DIR}/antgain" ] || \
   [ -f /etc/systemd/system/antgain.service ] || [ -f /etc/init.d/antgain ] || \
   [ -f "/Library/LaunchDaemons/${ANTGAIN_SERVICE_NAME}.plist" ] || \
   [ -x "$ANTGAIN_LINUX_START_SCRIPT" ]; then system_install=true; fi
if [ "$EUID" -ne 0 ]; then
  if [ "$system_install" = true ]; then
    # A piped script has no reusable $0. Download to a file before elevating.
    temporary="$(mktemp)"
    trap 'rm -f "$temporary"' EXIT
    curl --connect-timeout 15 --max-time 60 -fsSL "${ANTGAIN_INSTALL_BASE}/uninstall-cli.sh" -o "$temporary"
    sudo env ANTGAIN_UNINSTALL_SCOPE=system \
      ANTGAIN_UNINSTALL_YES="${ANTGAIN_UNINSTALL_YES:-}" ANTGAIN_UNINSTALL_PURGE="${ANTGAIN_UNINSTALL_PURGE:-}" \
      ANTGAIN_DATA_DIR="$ANTGAIN_DATA_DIR" ANTGAIN_INSTALL_DIR="$ANTGAIN_INSTALL_DIR" \
      ANTGAIN_SERVICE_NAME="$ANTGAIN_SERVICE_NAME" ANTGAIN_INSTALL_BASE="$ANTGAIN_INSTALL_BASE" \
      ANTGAIN_SERVICE_INSTALL_DIR="${ANTGAIN_SERVICE_INSTALL_DIR:-/usr/local/lib/antgain}" \
      ANTGAIN_LINUX_START_SCRIPT="$ANTGAIN_LINUX_START_SCRIPT" ANTGAIN_LINUX_ENV_FILE="$ANTGAIN_LINUX_ENV_FILE" \
      bash "$temporary"
  else
    ag_print_success 'User installation removed; saved data was preserved unless purged.'
  fi
  exit 0
fi

managed_dir="${ANTGAIN_SERVICE_INSTALL_DIR:-/usr/local/lib/antgain}"
if [ -L "${ANTGAIN_INSTALL_DIR}/antgain" ]; then
  target="$(readlink "${ANTGAIN_INSTALL_DIR}/antgain")"
  case "$target" in /*/antgain) managed_dir="$(dirname "$target")" ;; esac
fi
if [ -x "$ANTGAIN_LINUX_START_SCRIPT" ]; then "$ANTGAIN_LINUX_START_SCRIPT" stop || true; fi
case "$(uname -s)" in
  Linux*)
    if ag_has_systemd; then ag_remove_systemd_service; fi
    ag_remove_linux_fallback_service
    for link in /etc/rc*.d/S*antgain /etc/rc*.d/K*antgain; do
      if [ -L "$link" ] && [ "$(readlink "$link")" = ../init.d/antgain ]; then rm -f "$link"; fi
    done ;;
  Darwin*) ag_remove_launchd_service ;;
esac
remove_cli_files "$ANTGAIN_INSTALL_DIR"
if [ "$managed_dir" != "$ANTGAIN_INSTALL_DIR" ]; then
  remove_cli_files "$managed_dir"
  rmdir "$managed_dir" 2>/dev/null || true
fi
# Preserve other files in a custom install directory.
rm -f /usr/local/bin/antgain-uninstall
if command -v dpkg-query >/dev/null 2>&1 && dpkg-query -W antgain-cli >/dev/null 2>&1; then
  apt-get remove -y antgain-cli
fi
if [ -d "$ANTGAIN_DATA_DIR" ] && purge_requested; then remove_data "$ANTGAIN_DATA_DIR"; fi
ag_print_success 'AntGain CLI and startup registrations removed.'
ag_print_info 'Saved data is kept unless you chose to purge it. Docker containers are managed separately with docker stop/rm.'
