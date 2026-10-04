#!/bin/bash
set -euo pipefail
# Preserve both local and piped use of this published URL.
# Legacy `bash -s VALUE` puts its first argument in $0.
case "$0" in
  bash|/bin/bash|dash|/bin/dash|sh|/bin/sh|zsh|ksh|""|*.sh|/*) ;;
  *) set -- "$0" "$@" ;;
esac
root="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [ -f "${root}/install-cli.sh" ]; then
  exec bash "${root}/install-cli.sh" "$@"
fi
temporary="$(mktemp)"
trap 'rm -f "$temporary"' EXIT
curl --connect-timeout 15 --max-time 60 -fsSL "${ANTGAIN_INSTALL_BASE:-https://install.antgain.app}/install-cli.sh" -o "$temporary"
bash "$temporary" "$@"
