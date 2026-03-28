#!/usr/bin/env bash
set -uo pipefail

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

FAILED_ITEMS=()
SKIPPED_ITEMS=()

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This bootstrap script currently supports macOS only."
  exit 1
fi

echo "==> Bootstrap starting from: $DOTFILES_DIR"

# --- Homebrew ---
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

# --- Stage 1: Taps, formulae, and casks ---
echo "==> Installing packages from Brewfile (taps, formulae, casks)..."
if ! run brew bundle --file "$BREWFILE" --no-vscode --no-mas; then
  FAILED_ITEMS+=("[brew] bundle (taps, formulae, casks)")
fi

# --- Stage 2: Mac App Store apps (user choice) ---
mas_lines=()
while IFS= read -r line; do
  mas_lines+=("$line")
done < <(grep '^mas ' "$BREWFILE" 2>/dev/null || true)

if [[ ${#mas_lines[@]} -gt 0 ]]; then
  echo ""
  echo "==> Mac App Store apps (${#mas_lines[@]} available):"
  for line in "${mas_lines[@]}"; do
    app_name=$(echo "$line" | sed -E 's/^mas "([^"]+)".*/\1/')
    echo "     • $app_name"
  done
  echo ""
  read -rp "Install Mac App Store apps? This may take a long time. [y/N]: " install_mas
  install_mas_lower=$(echo "$install_mas" | tr '[:upper:]' '[:lower:]')
  if [[ "$install_mas_lower" == "y" || "$install_mas_lower" == "yes" ]]; then
    echo "==> Installing Mac App Store apps..."
    for line in "${mas_lines[@]}"; do
      app_name=$(echo "$line" | sed -E 's/^mas "([^"]+)".*/\1/')
      app_id=$(echo "$line" | sed -E 's/.*id: ([0-9]+).*/\1/')
      echo "  Installing: $app_name ($app_id)..."
      if ! run mas install "$app_id"; then
        FAILED_ITEMS+=("[mas] $app_name (id: $app_id)")
      fi
    done
  else
    echo "  Skipping Mac App Store apps."
    for line in "${mas_lines[@]}"; do
      app_name=$(echo "$line" | sed -E 's/^mas "([^"]+)".*/\1/')
      SKIPPED_ITEMS+=("[mas] $app_name")
    done
  fi
fi

# --- Dotfiles ---
echo "==> Applying dotfiles with stow..."
if ! run "$DOTFILES_DIR/bin/stow_all.sh"; then
  FAILED_ITEMS+=("[stow] dotfiles")
fi

# --- rebrew CLI ---
echo "==> Installing rebrew CLI..."
REBREW_LINK="/usr/local/bin/rebrew"
if [[ "$DRY_RUN" == "true" ]]; then
  echo "[dry-run] ln -sf $DOTFILES_DIR/bin/rebrew $REBREW_LINK"
else
  mkdir -p "$(dirname "$REBREW_LINK")"
  if ln -sf "$DOTFILES_DIR/bin/rebrew" "$REBREW_LINK"; then
    echo "  Linked: $REBREW_LINK → $DOTFILES_DIR/bin/rebrew"
  else
    FAILED_ITEMS+=("[rebrew] CLI symlink")
  fi
fi

# --- Git identity ---
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

# --- Node via nvm ---
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
    if nvm install --lts; then
      nvm alias default "lts/*" || true
    else
      FAILED_ITEMS+=("[nvm] Node LTS install")
    fi
  fi
else
  echo "WARNING: nvm.sh was not found; skipping Node installation."
fi

# --- Stage 3: VSCode extensions (parallel) ---
if command -v code >/dev/null 2>&1; then
  vscode_exts=()
  while IFS= read -r ext; do
    vscode_exts+=("$ext")
  done < <(grep '^vscode "' "$BREWFILE" | sed -E 's/^vscode "([^"]+)".*/\1/')

  if [[ ${#vscode_exts[@]} -gt 0 ]]; then
    echo "==> Installing ${#vscode_exts[@]} VSCode extensions in parallel..."
    if [[ "$DRY_RUN" == "true" ]]; then
      for ext in "${vscode_exts[@]}"; do
        echo "[dry-run] code --install-extension $ext --force"
      done
    else
      VSCODE_TMPDIR=$(mktemp -d)
      for ext in "${vscode_exts[@]}"; do
        (
          if ! code --install-extension "$ext" --force >"$VSCODE_TMPDIR/$ext.log" 2>&1; then
            touch "$VSCODE_TMPDIR/FAIL.$ext"
          fi
        ) &
      done
      wait
      for f in "$VSCODE_TMPDIR"/FAIL.*; do
        [[ -e "$f" ]] || continue
        ext="${f#$VSCODE_TMPDIR/FAIL.}"
        FAILED_ITEMS+=("[vscode] $ext")
      done
      rm -rf "$VSCODE_TMPDIR"
    fi
  fi
else
  echo "WARNING: 'code' command not found; skipping VSCode extension installation."
fi

# --- Final report ---
echo ""
echo "==> Bootstrap complete."

if [[ ${#SKIPPED_ITEMS[@]} -gt 0 ]]; then
  echo ""
  echo "  Skipped (${#SKIPPED_ITEMS[@]} item(s) — run 'rebrew bootstrap' to install):"
  for item in "${SKIPPED_ITEMS[@]}"; do
    echo "    - $item"
  done
fi

if [[ ${#FAILED_ITEMS[@]} -gt 0 ]]; then
  echo ""
  echo "  ✗ Failed (${#FAILED_ITEMS[@]} item(s) — run 'rebrew bootstrap' to retry):"
  for item in "${FAILED_ITEMS[@]}"; do
    echo "    - $item"
  done
  echo ""
  echo "Open a new terminal (or run: source ~/.zshrc) to load updated shell config."
  exit 1
fi

echo "  ✓ All items installed successfully."
echo ""
echo "Open a new terminal (or run: source ~/.zshrc) to load updated shell config."
