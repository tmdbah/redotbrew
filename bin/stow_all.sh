#!/usr/bin/env bash
# re.Brew — Symlink dotfile packages into $HOME using GNU Stow.
# https://github.com/tmdbah/redotbrew
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALL_PACKAGES=(zsh git vscode config ssh)

# --- Preflight checks ---
if ! command -v stow >/dev/null 2>&1; then
  echo "Error: GNU Stow is not installed." >&2
  echo "  Install it with: brew install stow" >&2
  exit 1
fi

# --- Parse arguments ---
DRY_RUN=0
ADOPT=0
PACKAGES=()
for arg in "$@"; do
  case "$arg" in
    -n|--dry-run) DRY_RUN=1 ;;
    --adopt) ADOPT=1 ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--dry-run|-n] [--adopt] [package ...]"
      echo ""
      echo "Symlink dotfile packages into \$HOME using GNU Stow."
      echo ""
      echo "Options:"
      echo "  --dry-run, -n   Preview changes without creating symlinks"
      echo "  --adopt         Adopt existing files into the repo (moves originals"
      echo "                  into the package dir, replaces with symlinks)"
      echo "  --help, -h      Show this help message"
      echo ""
      echo "Available packages: ${ALL_PACKAGES[*]}"
      echo "If no packages are specified, all packages are applied."
      exit 0
      ;;
    -*) echo "Unknown option: $arg" >&2; exit 1 ;;
    *) PACKAGES+=("$arg") ;;
  esac
done

# Default to all packages if none specified
if [[ ${#PACKAGES[@]} -eq 0 ]]; then
  PACKAGES=("${ALL_PACKAGES[@]}")
fi

# --- Validate package directories ---
missing=()
for pkg in "${PACKAGES[@]}"; do
  if [[ ! -d "$DOTFILES_DIR/$pkg" ]]; then
    missing+=("$pkg")
  fi
done
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Error: Package directories not found in $DOTFILES_DIR:" >&2
  printf '  %s\n' "${missing[@]}" >&2
  exit 1
fi

# --- Run stow ---
STOW_ARGS=(-d "$DOTFILES_DIR" -t "$HOME")
if [[ $ADOPT -eq 1 ]]; then
  STOW_ARGS+=(--adopt)
fi

if [[ $DRY_RUN -eq 1 ]]; then
  echo "[dry-run] Previewing symlinks for: ${PACKAGES[*]}"
  exec stow "${STOW_ARGS[@]}" -nv "${PACKAGES[@]}"
else
  if [[ $ADOPT -eq 1 ]]; then
    echo "Adopting existing files and applying packages: ${PACKAGES[*]}"
  else
    echo "Applying packages: ${PACKAGES[*]}"
  fi
  stow "${STOW_ARGS[@]}" "${PACKAGES[@]}"
  echo "Done. Symlinks created in $HOME."
fi
