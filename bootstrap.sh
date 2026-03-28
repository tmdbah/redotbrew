#!/usr/bin/env bash
# re.Brew — Full macOS bootstrap.
# https://github.com/tmdbah/redotbrew
#
# Usage:
#   ./bootstrap.sh [options]
#
# Options:
#   --dry-run, -n   Preview without making changes
#   --force         Reinstall existing casks / overwrite
#   --help, -h      Show this help message
set -uo pipefail

# ── Resolve repo root ────────────────────────────────────────────────────────
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BREWFILE="$DOTFILES_DIR/Brewfile"

# ── Source shared output helpers ─────────────────────────────────────────────
# shellcheck source=bin/lib/output.sh
. "$DOTFILES_DIR/bin/lib/output.sh"

# ── Parse arguments ──────────────────────────────────────────────────────────
DRY_RUN=false
FORCE=false
for arg in "$@"; do
  case "$arg" in
    -n|--dry-run) DRY_RUN=true ;;
    --force)      FORCE=true ;;
    -h|--help)
      cat <<EOF
re.Brew — Full macOS bootstrap

Usage: ./bootstrap.sh [OPTIONS]

Options:
  --dry-run, -n   Preview without making changes
  --force         Reinstall existing casks (brew install --cask --force)
  --help, -h      Show this help message
EOF
      exit 0
      ;;
    *) err "Unknown option: $arg"; exit 1 ;;
  esac
done

# ── Dry-run wrapper ──────────────────────────────────────────────────────────
run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] $*"
    return 0
  fi
  "$@"
}

# ── State tracking ───────────────────────────────────────────────────────────
FAILED_ITEMS=()
SKIPPED_ITEMS=()
SUCCESS_COUNT=0
BOOTSTRAP_START=$SECONDS

# ── Cleanup trap ─────────────────────────────────────────────────────────────
SUDO_PID=""
cleanup() {
  if [[ -n "$SUDO_PID" ]] && kill -0 "$SUDO_PID" 2>/dev/null; then
    kill "$SUDO_PID" 2>/dev/null || true
    wait "$SUDO_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# ── macOS guard ──────────────────────────────────────────────────────────────
if [[ "$(uname -s)" != "Darwin" ]]; then
  err "This bootstrap script currently supports macOS only."
  exit 1
fi

# ══════════════════════════════════════════════════════════════════════════════
# PRE-FLIGHT CHECKS
# ══════════════════════════════════════════════════════════════════════════════
info "Running pre-flight checks..."

# Phase 1A — Cache sudo credentials up front
if [[ "$DRY_RUN" != "true" ]]; then
  info "Requesting administrator privileges (used for cask installs)..."
  if sudo -v 2>/dev/null; then
    ok "sudo credentials cached"
    # Keep sudo alive in the background
    (while true; do sudo -n true 2>/dev/null; sleep 50; done) &
    SUDO_PID=$!
  else
    warn "Could not cache sudo credentials — cask installs may prompt repeatedly"
  fi
else
  echo "[dry-run] sudo -v"
fi

# Phase 1B — Xcode Command Line Tools
if xcode-select -p >/dev/null 2>&1; then
  ok "Xcode Command Line Tools installed"
else
  warn "Xcode Command Line Tools not found"
  if [[ "$DRY_RUN" != "true" ]]; then
    info "Installing Xcode Command Line Tools..."
    xcode-select --install 2>/dev/null || true
    echo "  Waiting for Xcode CLT installer — press any key once it finishes..."
    read -rsn1 2>/dev/null || true
  else
    echo "[dry-run] xcode-select --install"
  fi
fi

# ── Brewfile stats (Phase 5C — progress summary header) ─────────────────────
tap_count=$(grep -c '^tap ' "$BREWFILE" 2>/dev/null || echo 0)
formula_count=$(grep -c '^brew ' "$BREWFILE" 2>/dev/null || echo 0)
cask_count=$(grep -c '^cask ' "$BREWFILE" 2>/dev/null || echo 0)
mas_count=$(grep -c '^mas ' "$BREWFILE" 2>/dev/null || echo 0)
vscode_count=$(grep -c '^vscode ' "$BREWFILE" 2>/dev/null || echo 0)

echo ""
printf "${_BOLD}rebrew bootstrap${_RESET}\n"
echo "══════════════════════════════════════"
printf "  %-12s %s\n" "Taps:" "$tap_count"
printf "  %-12s %s\n" "Formulae:" "$formula_count"
printf "  %-12s %s\n" "Casks:" "$cask_count"
printf "  %-12s %s\n" "MAS apps:" "$mas_count"
printf "  %-12s %s\n" "VS Code:" "$vscode_count extensions"
echo "══════════════════════════════════════"
echo ""

info "Bootstrap starting from: $DOTFILES_DIR"

# ══════════════════════════════════════════════════════════════════════════════
# STAGE 0: HOMEBREW
# ══════════════════════════════════════════════════════════════════════════════
if ! command -v brew >/dev/null 2>&1; then
  info "Homebrew not found. Installing Homebrew..."
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
  else
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
else
  ok "Homebrew already installed"
fi

if command -v /opt/homebrew/bin/brew >/dev/null 2>&1; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif command -v /usr/local/bin/brew >/dev/null 2>&1; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# ══════════════════════════════════════════════════════════════════════════════
# STAGE 1: TAPS + FORMULAE (via brew bundle, excluding casks/mas/vscode)
# ══════════════════════════════════════════════════════════════════════════════
info "Installing taps and formulae from Brewfile..."
if ! run brew bundle --file "$BREWFILE" --no-cask --no-vscode --no-mas; then
  FAILED_ITEMS+=("[brew] bundle (taps + formulae)")
else
  ok "Taps and formulae installed"
  (( SUCCESS_COUNT++ ))
fi

# ══════════════════════════════════════════════════════════════════════════════
# STAGE 2: CASKS (individually, with skip-if-installed logic)
# ══════════════════════════════════════════════════════════════════════════════
cask_lines=()
while IFS= read -r line; do
  cask_lines+=("$line")
done < <(grep '^cask "' "$BREWFILE" | sed -E 's/^cask "([^"]+)".*/\1/')

if [[ ${#cask_lines[@]} -gt 0 ]]; then
  info "Installing ${#cask_lines[@]} casks..."
  # Build associative array of already-installed casks (O(1) lookup)
  declare -A installed_cask_set
  if [[ "$DRY_RUN" != "true" ]]; then
    while IFS= read -r c; do
      [[ -n "$c" ]] && installed_cask_set["$c"]=1
    done < <(brew list --cask 2>/dev/null || true)
  fi

  for cask_name in "${cask_lines[@]}"; do
    # Check if already installed
    if [[ "$DRY_RUN" != "true" ]] && [[ -n "${installed_cask_set[$cask_name]:-}" ]]; then
      if [[ "$FORCE" == "true" ]]; then
        info "Reinstalling cask: $cask_name (--force)"
        if ! brew install --cask --force --no-quarantine "$cask_name"; then
          FAILED_ITEMS+=("[cask] $cask_name")
        else
          (( SUCCESS_COUNT++ ))
        fi
      else
        ok "$cask_name already installed"
        SKIPPED_ITEMS+=("[cask] $cask_name (already installed)")
        (( SUCCESS_COUNT++ ))
      fi
    else
      if [[ "$DRY_RUN" == "true" ]]; then
        echo "[dry-run] brew install --cask --no-quarantine $cask_name"
      else
        if ! brew install --cask --no-quarantine "$cask_name"; then
          FAILED_ITEMS+=("[cask] $cask_name")
        else
          ok "$cask_name installed"
          (( SUCCESS_COUNT++ ))
        fi
      fi
    fi
  done
fi

# ══════════════════════════════════════════════════════════════════════════════
# STAGE 3: MAC APP STORE (with login check + user choice)
# ══════════════════════════════════════════════════════════════════════════════
mas_lines=()
while IFS= read -r line; do
  mas_lines+=("$line")
done < <(grep '^mas ' "$BREWFILE" 2>/dev/null || true)

if [[ ${#mas_lines[@]} -gt 0 ]]; then
  # Phase 1C + 4A — Check MAS availability and login
  mas_available=true
  mas_logged_in=true

  if ! command -v mas >/dev/null 2>&1; then
    warn "mas not installed — skipping Mac App Store apps"
    warn "Install with: brew install mas"
    mas_available=false
  fi

  if [[ "$mas_available" == "true" && "$DRY_RUN" != "true" ]]; then
    if ! mas account >/dev/null 2>&1; then
      warn "Not signed into the Mac App Store — skipping MAS apps"
      warn "Sign in via System Settings → Apple ID, then re-run bootstrap"
      mas_logged_in=false
    else
      ok "Mac App Store: signed in"
    fi
  fi

  # Phase 4C — Spotlight check
  if [[ "$mas_available" == "true" && "$mas_logged_in" == "true" && "$DRY_RUN" != "true" ]]; then
    if ! mdutil -s /Applications 2>/dev/null | grep -q "Indexing enabled" 2>/dev/null; then
      warn "Spotlight indexing may be disabled for /Applications — MAS installs could fail"
    fi
  fi

  if [[ "$mas_available" == "false" || "$mas_logged_in" == "false" ]]; then
    for line in "${mas_lines[@]}"; do
      app_name=$(echo "$line" | sed -E 's/^mas "([^"]+)".*/\1/')
      SKIPPED_ITEMS+=("[mas] $app_name (not signed in)")
    done
  else
    echo ""
    info "Mac App Store apps (${#mas_lines[@]} available):"
    for line in "${mas_lines[@]}"; do
      app_name=$(echo "$line" | sed -E 's/^mas "([^"]+)".*/\1/')
      echo "     • $app_name"
    done
    echo ""
    read -rp "Install Mac App Store apps? This may take a long time. [y/N]: " install_mas
    install_mas_lower=$(echo "$install_mas" | tr '[:upper:]' '[:lower:]')
    if [[ "$install_mas_lower" == "y" || "$install_mas_lower" == "yes" ]]; then
      info "Installing Mac App Store apps..."

      # Phase 4B — Build associative array of already-installed MAS app IDs
      declare -A installed_mas_set
      if [[ "$DRY_RUN" != "true" ]]; then
        while IFS= read -r mid; do
          [[ -n "$mid" ]] && installed_mas_set["$mid"]=1
        done < <(mas list 2>/dev/null | awk '{print $1}' || true)
      fi

      for line in "${mas_lines[@]}"; do
        app_name=$(echo "$line" | sed -E 's/^mas "([^"]+)".*/\1/')
        app_id=$(echo "$line" | sed -E 's/.*id: ([0-9]+).*/\1/')

        # Check if already installed
        if [[ "$DRY_RUN" != "true" ]] && [[ -n "${installed_mas_set[$app_id]:-}" ]]; then
          ok "$app_name already installed"
          (( SUCCESS_COUNT++ ))
          continue
        fi

        info "Installing: $app_name ($app_id)..."
        if ! run mas install "$app_id"; then
          FAILED_ITEMS+=("[mas] $app_name (id: $app_id)")
        else
          ok "$app_name installed"
          (( SUCCESS_COUNT++ ))
        fi
      done
    else
      info "Skipping Mac App Store apps."
      for line in "${mas_lines[@]}"; do
        app_name=$(echo "$line" | sed -E 's/^mas "([^"]+)".*/\1/')
        SKIPPED_ITEMS+=("[mas] $app_name")
      done
    fi
  fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# STAGE 4: DOTFILES (with stow availability check)
# ══════════════════════════════════════════════════════════════════════════════
# Phase 1D — Check stow is available before calling stow_all.sh
if command -v stow >/dev/null 2>&1; then
  info "Applying dotfiles with stow..."
  if ! run "$DOTFILES_DIR/bin/stow_all.sh"; then
    FAILED_ITEMS+=("[stow] dotfiles")
  else
    ok "Dotfiles applied"
    (( SUCCESS_COUNT++ ))
  fi
else
  warn "GNU Stow not found — skipping dotfile symlinks"
  warn "Install with: brew install stow"
  SKIPPED_ITEMS+=("[stow] dotfiles (stow not installed)")
fi

# ══════════════════════════════════════════════════════════════════════════════
# STAGE 5: REBREW CLI
# ══════════════════════════════════════════════════════════════════════════════
info "Installing rebrew CLI..."
REBREW_LINK="/usr/local/bin/rebrew"
if [[ "$DRY_RUN" == "true" ]]; then
  echo "[dry-run] ln -sf $DOTFILES_DIR/bin/rebrew $REBREW_LINK"
else
  mkdir -p "$(dirname "$REBREW_LINK")"
  if ln -sf "$DOTFILES_DIR/bin/rebrew" "$REBREW_LINK"; then
    ok "Linked: $REBREW_LINK → $DOTFILES_DIR/bin/rebrew"
    (( SUCCESS_COUNT++ ))
  else
    FAILED_ITEMS+=("[rebrew] CLI symlink")
  fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# STAGE 6: GIT IDENTITY
# ══════════════════════════════════════════════════════════════════════════════
GIT_LOCAL="$HOME/.gitconfig.local"
if [[ ! -f "$GIT_LOCAL" ]]; then
  info "Setting up Git identity..."
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
    ok "Git identity saved to $GIT_LOCAL"
    (( SUCCESS_COUNT++ ))
  fi
else
  ok "Git identity already configured ($GIT_LOCAL)"
fi

# ══════════════════════════════════════════════════════════════════════════════
# STAGE 7: NODE VIA NVM
# ══════════════════════════════════════════════════════════════════════════════
NVM_SH=""
if [[ -s "/opt/homebrew/opt/nvm/nvm.sh" ]]; then
  NVM_SH="/opt/homebrew/opt/nvm/nvm.sh"
elif [[ -s "/usr/local/opt/nvm/nvm.sh" ]]; then
  NVM_SH="/usr/local/opt/nvm/nvm.sh"
fi

if [[ -n "$NVM_SH" ]]; then
  info "Installing Node LTS via nvm..."
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
      ok "Node LTS installed via nvm"
      (( SUCCESS_COUNT++ ))
    else
      FAILED_ITEMS+=("[nvm] Node LTS install")
    fi
  fi
else
  warn "nvm.sh was not found — skipping Node installation"
  SKIPPED_ITEMS+=("[nvm] Node LTS (nvm not found)")
fi

# ══════════════════════════════════════════════════════════════════════════════
# STAGE 8: VSCODE EXTENSIONS (after casks are settled)
# ══════════════════════════════════════════════════════════════════════════════
# Phase 3A — Resolve the `code` CLI, even if it was just installed as a cask
VSCODE_CMD=""
if command -v code >/dev/null 2>&1; then
  VSCODE_CMD="code"
elif [[ -x "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" ]]; then
  VSCODE_CMD="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
  info "Found VSCode at application path (not yet on PATH)"
fi

if [[ -n "$VSCODE_CMD" ]]; then
  vscode_exts=()
  while IFS= read -r ext; do
    vscode_exts+=("$ext")
  done < <(grep '^vscode "' "$BREWFILE" | sed -E 's/^vscode "([^"]+)".*/\1/')

  if [[ ${#vscode_exts[@]} -gt 0 ]]; then
    info "Installing ${#vscode_exts[@]} VSCode extensions in parallel..."
    if [[ "$DRY_RUN" == "true" ]]; then
      for ext in "${vscode_exts[@]}"; do
        echo "[dry-run] $VSCODE_CMD --install-extension $ext --force"
      done
    else
      VSCODE_TMPDIR=$(mktemp -d)
      for ext in "${vscode_exts[@]}"; do
        (
          if ! "$VSCODE_CMD" --install-extension "$ext" --force >"$VSCODE_TMPDIR/$ext.log" 2>&1; then
            touch "$VSCODE_TMPDIR/FAIL.$ext"
          fi
        ) &
      done
      wait

      ext_fail=0
      for f in "$VSCODE_TMPDIR"/FAIL.*; do
        [[ -e "$f" ]] || continue
        ext="${f#$VSCODE_TMPDIR/FAIL.}"
        FAILED_ITEMS+=("[vscode] $ext")
        (( ext_fail++ ))
      done
      ext_ok=$(( ${#vscode_exts[@]} - ext_fail ))
      (( SUCCESS_COUNT += ext_ok ))
      if [[ "$ext_fail" -eq 0 ]]; then
        ok "All ${#vscode_exts[@]} VSCode extensions installed"
      else
        warn "$ext_ok of ${#vscode_exts[@]} extensions installed ($ext_fail failed)"
      fi
      rm -rf "$VSCODE_TMPDIR"
    fi
  fi
else
  warn "'code' command not found — skipping VSCode extension installation"
  warn "Install VSCode first (brew install --cask visual-studio-code) then re-run bootstrap"
  SKIPPED_ITEMS+=("[vscode] extensions (VSCode not installed)")
fi

# ══════════════════════════════════════════════════════════════════════════════
# FINAL REPORT (Phase 5D)
# ══════════════════════════════════════════════════════════════════════════════
elapsed=$(( SECONDS - BOOTSTRAP_START ))
elapsed_min=$(( elapsed / 60 ))
elapsed_sec=$(( elapsed % 60 ))

echo ""
printf "${_BOLD}rebrew bootstrap — complete${_RESET}\n"
echo "══════════════════════════════════════"
printf "  ${_GREEN}✓ Succeeded:${_RESET}  %s\n" "$SUCCESS_COUNT"
printf "  ${_YELLOW}⚠ Skipped:${_RESET}    %s\n" "${#SKIPPED_ITEMS[@]}"
printf "  ${_RED}✖ Failed:${_RESET}     %s\n" "${#FAILED_ITEMS[@]}"
printf "  ${_DIM}⏱ Elapsed:     %dm %ds${_RESET}\n" "$elapsed_min" "$elapsed_sec"
echo "══════════════════════════════════════"

if [[ ${#SKIPPED_ITEMS[@]} -gt 0 ]]; then
  echo ""
  printf "  ${_YELLOW}Skipped (${#SKIPPED_ITEMS[@]}):${_RESET}\n"
  for item in "${SKIPPED_ITEMS[@]}"; do
    printf "    ${_DIM}- %s${_RESET}\n" "$item"
  done
fi

if [[ ${#FAILED_ITEMS[@]} -gt 0 ]]; then
  echo ""
  printf "  ${_RED}Failed (${#FAILED_ITEMS[@]}):${_RESET}\n"
  for item in "${FAILED_ITEMS[@]}"; do
    printf "    ${_RED}- %s${_RESET}\n" "$item"
  done

  # Phase 5D — Context-aware next-step suggestions (deduplicated by category)
  echo ""
  info "Suggested next steps:"
  declare -A _shown_hints
  for item in "${FAILED_ITEMS[@]}"; do
    hint=""
    case "$item" in
      "[mas]"*)    hint="Sign into the App Store and run: rebrew bootstrap" ;;
      "[cask]"*)   hint="Try: rebrew bootstrap --force (reinstalls existing casks)" ;;
      "[vscode]"*) hint="Ensure VSCode is installed, then: rebrew bootstrap" ;;
      "[stow]"*)   hint="Install stow (brew install stow) and run: rebrew stow" ;;
      "[nvm]"*)    hint="Check nvm setup and run: nvm install --lts" ;;
      *)           hint="Re-run: rebrew bootstrap" ;;
    esac
    if [[ -z "${_shown_hints[$hint]:-}" ]]; then
      echo "  → $hint"
      _shown_hints["$hint"]=1
    fi
  done

  echo ""
  echo "Open a new terminal (or run: source ~/.zshrc) to load updated shell config."
  exit 1
fi

echo ""
ok "All items installed successfully."
echo ""
echo "Open a new terminal (or run: source ~/.zshrc) to load updated shell config."
