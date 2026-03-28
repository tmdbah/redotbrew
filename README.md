# re.Brew

_Your dotfiles, re-brewed._

Audit, migrate, and automate your Mac setup through Homebrew. re.Brew scans what you have, shows what can be managed by brew, and syncs your configs across machines via Git.

## Quick Start

1. Clone this repository:
   ```sh
   git clone https://github.com/tmdbah/redotbrew.git ~/.redotbrew
   cd ~/.redotbrew
   ```
2. Run the bootstrap script:

   ```sh
   ./bootstrap.sh
   ```

   This installs Homebrew (if missing), all packages from the Brewfile, applies dotfile symlinks, prompts for your Git identity, initializes Node via nvm, and installs the `rebrew` CLI so you can run commands from anywhere.

   Preview first with:

   ```sh
   ./bootstrap.sh --dry-run
   ```

3. Use the CLI for everything after that:

   ```sh
   rebrew scan        # Audit installed apps and check Homebrew availability
   rebrew sync        # Sync Brewfile with actually installed packages
   rebrew stow        # Apply dotfile symlinks
   rebrew bootstrap   # Re-run the full setup
   rebrew help        # Show all commands
   rebrew version     # Print version
   ```

## CLI Reference

### `rebrew bootstrap`

Runs the full macOS setup: Homebrew install, `brew bundle`, dotfile symlinks, Git identity, and Node LTS.

The bootstrap is designed to be **resilient on real machines**:

- **Pre-flight checks** — validates Xcode CLT, sudo access, MAS login, and Spotlight before starting
- **Skip-if-installed** — casks already in `/Applications` are skipped instead of erroring
- **Dependency ordering** — VSCode extensions only install after VSCode itself is confirmed available
- **Structured output** — clear `✓ / ⚠ / ✖` progress indicators instead of raw Homebrew noise
- **Graceful failures** — individual failures are tracked and reported without crashing the entire run

```sh
rebrew bootstrap             # Full setup
rebrew bootstrap --dry-run   # Preview without making changes
rebrew bootstrap --force     # Reinstall existing casks
```

### `rebrew scan`

Scans installed macOS apps and CLI tools, classifies each by install source, and checks Homebrew availability. Generates a CSV and an interactive HTML dashboard.

```sh
rebrew scan                                # Default output to ~/Downloads
rebrew scan --output-dir ~/Desktop         # Custom output directory
rebrew scan --extra-paths ~/.cargo/bin     # Include extra binary directories
```

**Prerequisites:**
- **Homebrew** — required for availability checking
- **mas** (optional) — enables Mac App Store detection (`brew install mas`)

**Outputs:**
| File | Description |
|------|-------------|
| `installed_apps_audit.csv` | Raw data for scripting or spreadsheets |
| `installed_apps_audit.html` | Interactive dashboard with filtering, search, and charts |

### `rebrew stow`

Manages dotfile symlinks via GNU Stow. Packages: `zsh`, `git`, `vscode`, `config`, `ssh`.

```sh
rebrew stow                    # Apply all packages
rebrew stow --dry-run          # Preview changes
rebrew stow git zsh            # Apply specific packages only
rebrew stow --adopt            # Adopt existing files into repo, then symlink
rebrew stow --help             # Show stow-specific options
```

> **Tip:** If Stow reports a conflict (existing file in `$HOME`), use `--adopt` to pull the existing file into the repo and replace it with a symlink. Review the diff afterward to keep the version you want.

### `rebrew sync`

Compares the current Homebrew state against your repo Brewfile and shows what's drifted. Optionally updates the Brewfile and commits.

```sh
rebrew sync                # Interactive — show diff, prompt for action
rebrew sync --dry-run      # Show diff only, no changes
rebrew sync --apply        # Overwrite Brewfile with current state
rebrew sync --commit       # Apply + git commit
```

**Typical workflow:**

1. Install or remove a package with `brew install`/`brew uninstall`
2. Run `rebrew sync` to see the drift
3. Choose to apply, commit, or skip

## Structure

- **bin/rebrew**: CLI entry point — routes subcommands to the scripts below.
- **bin/lib/output.sh**: Shared output helpers (colors, `info`/`ok`/`warn`/`err`) used by all scripts.
- **bin/sync.sh**: Brewfile sync logic (used by `rebrew sync`).
- **bootstrap.sh**: Full macOS setup orchestration.
- **Brewfile**: Homebrew package manifest.
- **bin/scan_apps_brew_check.sh**: App audit and Homebrew availability checker.
- **bin/stow_all.sh**: GNU Stow wrapper for dotfile symlinks.
- **config/**: Tool configuration files (e.g., Starship prompt).
- **git/**: Git configuration.
- **vscode/**: VS Code settings and extensions.
- **zsh/**: Zsh shell configuration.

## Personalize

`bootstrap.sh` automatically prompts for your Git identity on first run and saves it to `~/.gitconfig.local` (gitignored, never committed). The repo's `git/.gitconfig` pulls it in via `[include]`.

To update your identity later:

```sh
git config --file ~/.gitconfig.local user.name "Your Name"
git config --file ~/.gitconfig.local user.email "your-email@example.com"
```

> **Tip:** Use your [GitHub noreply email](https://docs.github.com/en/account-and-profile/setting-up-and-managing-your-personal-account-on-github/managing-email-preferences/setting-your-commit-email-address) for privacy.

## Manual CLI Install

If you prefer not to run bootstrap, you can install the CLI manually:

```sh
ln -sf "$(pwd)/bin/rebrew" /usr/local/bin/rebrew
```

## Notes

- The Brewfile ensures all essential packages are installed via Homebrew.
- Configuration folders are organized by tool for easy management.

---

## Acknowledgments

**redotbrew** is built on the shoulders of two exceptional open-source tools:

- **[Homebrew](https://brew.sh)** — the Missing Package Manager for macOS. re.Brew's entire Brewfile-driven workflow, app audit, and reproducible setup story would not be possible without Homebrew and its vast formula/cask ecosystem. Huge thanks to the Homebrew maintainers and community.

- **[GNU Stow](https://www.gnu.org/software/stow/)** — the elegant symlink farm manager. The `stow_all.sh` script and all dotfile management in re.Brew are powered by GNU Stow. Its simple, reliable approach to symlinking config packages is what makes version-controlled dotfiles so portable. Thanks to the GNU Stow maintainers for such an indispensable utility.

---

**redotbrew** — _re.Brew_ | Your dotfiles, re-brewed.

Feel free to modify these files to suit your workflow.
