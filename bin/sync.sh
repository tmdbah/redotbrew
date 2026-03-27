#!/usr/bin/env bash
# re.Brew — Sync Brewfile with currently installed Homebrew packages.
# https://github.com/tmdbah/redotbrew
#
# Usage:
#   rebrew sync [options]
#
# Dumps the current Homebrew state, diffs it against the repo Brewfile,
# and optionally applies changes or commits them to Git.
set -euo pipefail

# ── Resolve repo root ────────────────────────────────────────────────────────
SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SYNC_BIN_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
REBREW_ROOT="$(cd "$SYNC_BIN_DIR/.." && pwd)"

BREWFILE="$REBREW_ROOT/Brewfile"

# ── Colors ───────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  YELLOW='\033[0;33m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  DIM='\033[2m'
  RESET='\033[0m'
else
  GREEN='' RED='' YELLOW='' CYAN='' BOLD='' DIM='' RESET=''
fi

info()  { printf "${CYAN}==> %s${RESET}\n" "$*"; }
ok()    { printf "${GREEN} ✓  %s${RESET}\n" "$*"; }
warn()  { printf "${YELLOW} ⚠  %s${RESET}\n" "$*"; }
err()   { printf "${RED} ✖  %s${RESET}\n" "$*" >&2; }

# ── Help ─────────────────────────────────────────────────────────────────────
show_help() {
  cat <<EOF
re.Brew — Sync Brewfile
Usage: rebrew sync [OPTIONS]

Compare the current Homebrew state against the repo Brewfile, then
optionally update the Brewfile and commit the changes.

Options:
  --apply        Overwrite the Brewfile with current Homebrew state (no prompt)
  --commit       Apply and commit the updated Brewfile to Git
  --dry-run, -n  Show the diff only; make no changes
  --help, -h     Show this help message

Interactive mode (default):
  When run with no flags, shows the diff and prompts for an action.
EOF
  exit 0
}

# ── Parse arguments ──────────────────────────────────────────────────────────
MODE="interactive"   # interactive | apply | commit | dry-run
for arg in "$@"; do
  case "$arg" in
    --apply)        MODE="apply" ;;
    --commit)       MODE="commit" ;;
    -n|--dry-run)   MODE="dry-run" ;;
    -h|--help)      show_help ;;
    *)
      err "Unknown option: $arg"
      echo "Run 'rebrew sync --help' for usage." >&2
      exit 1
      ;;
  esac
done

# ── Preflight ────────────────────────────────────────────────────────────────
if ! command -v brew >/dev/null 2>&1; then
  err "Homebrew is not installed. Install it first:"
  echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"" >&2
  exit 1
fi

if [[ ! -f "$BREWFILE" ]]; then
  err "Brewfile not found at $BREWFILE"
  exit 1
fi

# ── Dump current state ───────────────────────────────────────────────────────
TMPFILE="$(mktemp /tmp/rebrew-sync.XXXXXX)"
trap 'rm -f "$TMPFILE"' EXIT

info "Capturing current Homebrew state..."
brew bundle dump --file="$TMPFILE" --force --quiet 2>/dev/null

# ── Normalize for comparison ─────────────────────────────────────────────────
# Sort both files so the diff focuses on content, not ordering.
normalize() {
  # Strip blank lines and comments, then sort
  grep -v '^\s*$' "$1" | grep -v '^\s*#' | sort
}

NORM_CURRENT="$(mktemp /tmp/rebrew-norm-current.XXXXXX)"
NORM_REPO="$(mktemp /tmp/rebrew-norm-repo.XXXXXX)"
trap 'rm -f "$TMPFILE" "$NORM_CURRENT" "$NORM_REPO"' EXIT

normalize "$TMPFILE"   > "$NORM_CURRENT"
normalize "$BREWFILE"  > "$NORM_REPO"

# ── Compute diff ─────────────────────────────────────────────────────────────
ADDITIONS="$(comm -23 "$NORM_CURRENT" "$NORM_REPO")" || true
REMOVALS="$(comm -13 "$NORM_CURRENT" "$NORM_REPO")" || true
UNCHANGED="$(comm -12 "$NORM_CURRENT" "$NORM_REPO")" || true

add_count=0
rem_count=0
same_count=0
[[ -n "$ADDITIONS" ]] && add_count="$(echo "$ADDITIONS" | wc -l | tr -d ' ')"
[[ -n "$REMOVALS" ]]  && rem_count="$(echo "$REMOVALS"  | wc -l | tr -d ' ')"
[[ -n "$UNCHANGED" ]] && same_count="$(echo "$UNCHANGED" | wc -l | tr -d ' ')"

# ── Display drift report ────────────────────────────────────────────────────
echo ""
printf "${BOLD}rebrew sync — Brewfile drift report${RESET}\n"
echo "═══════════════════════════════════════"
echo ""

if [[ -n "$ADDITIONS" ]]; then
  while IFS= read -r line; do
    printf "${GREEN}+ %s${RESET}  ${DIM}← installed, not in Brewfile${RESET}\n" "$line"
  done <<< "$ADDITIONS"
fi

if [[ -n "$REMOVALS" ]]; then
  while IFS= read -r line; do
    printf "${RED}- %s${RESET}  ${DIM}← in Brewfile, not installed${RESET}\n" "$line"
  done <<< "$REMOVALS"
fi

if [[ "$add_count" -eq 0 && "$rem_count" -eq 0 ]]; then
  ok "Brewfile is in sync — no drift detected."
  echo ""
  printf "  ${DIM}%s entries match${RESET}\n" "$same_count"
  echo ""
  exit 0
fi

echo ""
printf "  ${DIM}%s added · %s removed · %s unchanged${RESET}\n" "$add_count" "$rem_count" "$same_count"
echo ""

# ── Act on mode ──────────────────────────────────────────────────────────────
apply_changes() {
  info "Updating Brewfile..."
  cp "$TMPFILE" "$BREWFILE"
  ok "Brewfile updated with current Homebrew state."
}

commit_changes() {
  apply_changes
  info "Committing Brewfile..."
  cd "$REBREW_ROOT"
  git add Brewfile
  git commit -m "rebrew sync: update Brewfile"
  ok "Committed. Run 'git push' when ready."
}

case "$MODE" in
  dry-run)
    info "Dry run — no changes made."
    ;;
  apply)
    apply_changes
    ;;
  commit)
    commit_changes
    ;;
  interactive)
    printf "${BOLD}What would you like to do?${RESET}\n"
    echo "  [a] Apply  — overwrite Brewfile with current state"
    echo "  [c] Commit — apply + git commit"
    echo "  [s] Skip   — do nothing"
    echo ""
    while true; do
      read -rp "Choice [a/c/s]: " choice
      case "$choice" in
        a|A) apply_changes; break ;;
        c|C) commit_changes; break ;;
        s|S) info "Skipped — no changes made."; break ;;
        *)   echo "  Please enter a, c, or s." ;;
      esac
    done
    ;;
esac
