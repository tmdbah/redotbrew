# Dotfiles

This repository contains configuration files and scripts to set up and customize your development environment on macOS.

## Structure

- **bootstrap.sh**: Main setup script to install and configure essential tools and settings.
- **Brewfile**: List of Homebrew packages and casks to be installed for system setup.
- **bin/**: Custom scripts for automation and system checks.
  - scan_apps_brew_check.sh: Script to scan installed applications and check against Homebrew.
  - stow_all.sh: Apply all dotfile packages with GNU Stow (`--dry-run` supported).
- **config/**: Configuration files for various tools and environments.
- **git/**: Git configuration files and templates.
- **shell/**: Shell configuration files (e.g., bash, zsh).
- **ssh/**: SSH configuration and keys.
- **vscode/**: VS Code settings and snippets.
- **zsh/**: Zsh-specific configuration files.

## Usage

1. Clone this repository:
   ```sh
   git clone https://github.com/yourusername/dotfiles.git
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
3. Apply dotfiles with Stow manually (optional, already done by bootstrap):
   ```sh
   ./bin/stow_all.sh --dry-run
   ./bin/stow_all.sh
   ```
4. Review and customize configuration files as needed.

## Notes

- The Brewfile ensures all essential packages are installed via Homebrew.
- Scripts in bin/ can be used for auditing and automation.
- Configuration folders are organized by tool for easy management.

---

Feel free to modify these files to suit your workflow.
