# Dotfiles

This repository contains configuration files and scripts to set up and customize your development environment on macOS.

## Structure

- **bootstrap.sh**: Main setup script to install and configure essential tools and settings.
- **Brewfile**: List of Homebrew packages and casks to be installed for system setup.
- **bin/**: Custom scripts for automation and system checks.
  - scan_apps_brew_check.sh: Script to scan installed applications and check against Homebrew.
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
3. Review and customize configuration files as needed.

## Notes

- The Brewfile ensures all essential packages are installed via Homebrew.
- Scripts in bin/ can be used for auditing and automation.
- Configuration folders are organized by tool for easy management.

---

Feel free to modify these files to suit your workflow.
