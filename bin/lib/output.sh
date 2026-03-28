#!/usr/bin/env bash
# re.Brew — Shared output helpers.
# Source this file to get consistent colored output across all rebrew scripts.
# https://github.com/tmdbah/redotbrew

# ── Colors (auto-disabled when not connected to a terminal) ──────────────────
if [[ -t 1 ]]; then
  _GREEN='\033[0;32m'
  _RED='\033[0;31m'
  _YELLOW='\033[0;33m'
  _CYAN='\033[0;36m'
  _BOLD='\033[1m'
  _DIM='\033[2m'
  _RESET='\033[0m'
else
  _GREEN='' _RED='' _YELLOW='' _CYAN='' _BOLD='' _DIM='' _RESET=''
fi

# ── Logging helpers ──────────────────────────────────────────────────────────
info()  { printf "${_CYAN}==> %s${_RESET}\n" "$*"; }
ok()    { printf "${_GREEN} ✓  %s${_RESET}\n" "$*"; }
warn()  { printf "${_YELLOW} ⚠  %s${_RESET}\n" "$*" >&2; }
err()   { printf "${_RED} ✖  %s${_RESET}\n" "$*" >&2; }

# ── Preflight helper ────────────────────────────────────────────────────────
# Usage: require_command <cmd> <friendly-name> <install-hint>
require_command() {
  local cmd="$1" name="${2:-$1}" hint="${3:-}"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    if [[ -n "$hint" ]]; then
      err "$name is not installed. $hint"
    else
      err "$name is not installed."
    fi
    return 1
  fi
  return 0
}
