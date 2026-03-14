#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGES=(zsh git vscode config ssh)

if [[ "${1:-}" == "-n" || "${1:-}" == "--dry-run" ]]; then
  exec stow -d "$DOTFILES_DIR" -t "$HOME" -nv "${PACKAGES[@]}"
fi

exec stow -d "$DOTFILES_DIR" -t "$HOME" "${PACKAGES[@]}"
