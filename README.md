# re.Brew

*Your dotfiles, re-brewed.*

Audit, migrate, and automate your Mac setup through Homebrew. re.Brew scans what you have, shows what can be managed by brew, and syncs your configs across machines via Git.

## Structure

- **bootstrap.sh**: Main setup script to install and configure essential tools and settings.
- **Brewfile**: List of Homebrew packages and casks to be installed for system setup.
- **bin/**: Custom scripts for automation and system checks.
  - `scan_apps_brew_check.sh`: Audit installed apps/tools and identify candidates for Brewfile migration.
  - `stow_all.sh`: Symlink dotfile packages into `$HOME` via GNU Stow for version-controlled config management.
- **config/**: Configuration files for various tools and environments.
- **git/**: Git configuration files and templates.
- **shell/**: Shell configuration files (e.g., bash, zsh).
- **ssh/**: SSH configuration and keys.
- **vscode/**: VS Code settings and snippets.
- **zsh/**: Zsh-specific configuration files.

## Quick Start

1. Clone this repository:
   ```sh
   git clone https://github.com/tmdbah/redotbrew.git
   ```
2. Run the bootstrap script:

   ```sh
   ./bootstrap.sh
   ```

   What `bootstrap.sh` does:
   - Installs Homebrew (if missing) and loads Homebrew environment.
   - Runs `brew bundle --file Brewfile`.
   - Applies dotfiles via `./bin/stow_all.sh`.
   - Initializes `nvm` and installs Node LTS as the default version.

   You can preview actions with:

   ```sh
   ./bootstrap.sh --dry-run
   ```

## Manage Dotfiles with Stow

GNU Stow creates symlinks from organized package directories in this repo into `$HOME`, so your configs are version-controlled and portable across machines via Git.

**Packages:** `zsh`, `git`, `vscode`, `config`, `ssh`
(e.g., `zsh/.zshrc` → `~/.zshrc` as a symlink)

```sh
# Preview what will be linked (no changes made)
./bin/stow_all.sh --dry-run

# Apply all packages
./bin/stow_all.sh

# Apply specific packages only
./bin/stow_all.sh zsh git

# Resolve conflicts: adopt existing files into the repo, then symlink
./bin/stow_all.sh --adopt

# Show help
./bin/stow_all.sh --help
```

> **Tip:** If Stow reports a conflict (existing file in `$HOME`), use `--adopt` to pull the existing file into the repo and replace it with a symlink. Review the diff afterward to keep the version you want.

## Installed Apps Audit

`scan_apps_brew_check.sh` scans your macOS apps and CLI tools, classifies each by install source, and checks whether they're available in Homebrew. The goal: **find everything you installed manually that _could_ be in your Brewfile** — so you can automate your full Mac setup.

**Prerequisites:**

- **Homebrew** — required for availability checking (script runs without it, but with limited data)
- **mas** (optional) — enables Mac App Store app detection (`brew install mas`)

```sh
# Run with defaults (outputs to ~/Downloads)
./bin/scan_apps_brew_check.sh

# Custom output directory
./bin/scan_apps_brew_check.sh --output-dir ~/Desktop

# Include extra directories (e.g. pip, cargo, go bins)
./bin/scan_apps_brew_check.sh --extra-paths ~/.local/bin:~/.cargo/bin

# Open the interactive HTML dashboard
open ~/Downloads/installed_apps_audit.html
```

**Outputs:**
| File | Description |
|------|-------------|
| `installed_apps_audit.csv` | Raw data for scripting or spreadsheets |
| `installed_apps_audit.html` | Interactive dashboard with filtering, search, and charts |

**What gets scanned:**

- Apps in `/Applications` and `~/Applications`
- CLI tools in `/usr/local/bin` and `/opt/homebrew/bin` (plus any `--extra-paths`)
- Version detection runs in parallel (8 concurrent workers) for faster scans

**Output categories:**
| Category | What it means | Action |
|----------|---------------|--------|
| **Installed via Homebrew** | Already managed by brew | Keep as-is in Brewfile |
| **Manual but Homebrew available** | Installed manually, but brew has it | Add to Brewfile for automation |
| **Manual and not in Homebrew** | No brew package exists | Keep manual or find alternative |

**Typical workflow:**

1. Run the scan on your current setup
2. Open the HTML dashboard and filter to "Manual but Homebrew available"
3. Add those items to your `Brewfile`
4. Run `brew bundle` to verify
5. Re-scan to confirm coverage

## Notes

- The Brewfile ensures all essential packages are installed via Homebrew.
- Configuration folders are organized by tool for easy management.

---

**redotbrew** — *re.Brew* | Your dotfiles, re-brewed.

Feel free to modify these files to suit your workflow.
