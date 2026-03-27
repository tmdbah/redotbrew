#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]]; then
  DRY_RUN=true
fi

run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] $*"
    return 0
  fi
  "$@"
}

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BREWFILE="$DOTFILES_DIR/Brewfile"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This bootstrap script currently supports macOS only."
  exit 1
fi

echo "==> Bootstrap starting from: $DOTFILES_DIR"

if ! command -v brew >/dev/null 2>&1; then
  echo "==> Homebrew not found. Installing Homebrew..."
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
  else
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
fi

if command -v /opt/homebrew/bin/brew >/dev/null 2>&1; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif command -v /usr/local/bin/brew >/dev/null 2>&1; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

echo "==> Installing packages from Brewfile..."
run brew bundle --file "$BREWFILE"

echo "==> Applying dotfiles with stow..."
run "$DOTFILES_DIR/bin/stow_all.sh"

GIT_LOCAL="$HOME/.gitconfig.local"
if [[ ! -f "$GIT_LOCAL" ]]; then
  echo "==> Setting up Git identity..."
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] Prompt for Git name and email, write to $GIT_LOCAL"
  else
    read -rp "Your full name for Git commits: " git_name
    read -rp "Your email for Git commits: " git_email
    cat > "$GIT_LOCAL" <<EOF
[user]
	name = $git_name
	email = $git_email
EOF
    echo "  Saved to $GIT_LOCAL"
  fi
fi

NVM_SH=""
if [[ -s "/opt/homebrew/opt/nvm/nvm.sh" ]]; then
  NVM_SH="/opt/homebrew/opt/nvm/nvm.sh"
elif [[ -s "/usr/local/opt/nvm/nvm.sh" ]]; then
  NVM_SH="/usr/local/opt/nvm/nvm.sh"
fi

if [[ -n "$NVM_SH" ]]; then
  echo "==> Installing Node LTS via nvm..."
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] export NVM_DIR=\"$HOME/.nvm\""
    echo "[dry-run] mkdir -p \"$HOME/.nvm\""
    echo "[dry-run] . \"$NVM_SH\""
    echo "[dry-run] nvm install --lts"
    echo "[dry-run] nvm alias default \"lts/*\""
  else
    export NVM_DIR="$HOME/.nvm"
    mkdir -p "$NVM_DIR"
    # shellcheck source=/dev/null
    . "$NVM_SH"
    nvm install --lts
    nvm alias default "lts/*"
  fi
else
  echo "WARNING: nvm.sh was not found; skipping Node installation."
fi

echo "==> Bootstrap complete."
echo "Open a new terminal (or run: source ~/.zshrc) to load updated shell config."
