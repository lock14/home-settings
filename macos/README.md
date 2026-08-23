# macOS Setup & Development Environment

This directory contains automated setup scripts and terminal configuration for macOS (Darwin), mirroring the existing Ubuntu and Fedora provisioning pipelines while adhering to native macOS best practices.

---

## Quick Start

Run the automated setup script:

```bash
# Standard setup with default settings (OpenJDK 11, IntelliJ Ultimate, Terminal.app)
./macos/macos_setup.sh
```

### Options & Flags

```text
usage: macos_setup.sh [options]

Options:
  -j, --jdk <package>   JDK to install: openjdk-8, openjdk-11, openjdk-17, openjdk-21, none (default: openjdk-11)
  -i, --ide <ide>       IDE to install: intellij, intellij-ultimate, vscode, none (default: intellij-ultimate)
  --iterm2              Install and configure iTerm2 (Dynamic Profile)
  --ghostty             Install and configure Ghostty (~/.config/ghostty/config)
  --apps                Install productivity apps (Google Chrome, Slack, Postman)
  --dry-run             Show actions without executing
  -h, --help            Show help message
```

#### Examples:

```bash
# Install with Visual Studio Code and Ghostty
./macos/macos_setup.sh --ide vscode --ghostty

# Install with iTerm2 and extra productivity apps
./macos/macos_setup.sh --iterm2 --apps

# Dry-run preview
./macos/macos_setup.sh --iterm2 --ghostty --dry-run
```

---

## Terminal Configuration

Terminal appearance is configured with **Solarized Dark** and **MesloLGS NF** Powerlevel10k fonts.

* **Apple Terminal.app (Default):** Pre-configured via `Solarized Dark.terminal` and set as the default startup profile.
* **iTerm2 (Optional):** Automated using iTerm2 Dynamic Profiles (`~/Library/Application Support/iTerm2/DynamicProfiles/solarized-dark.json`).
* **Ghostty (Optional):** Automated via `~/.config/ghostty/config`.

To configure terminals independently:
```bash
# Configure only Apple Terminal.app
./macos/terminal-setup.sh --terminal-only

# Configure all supported terminal emulators
./macos/terminal-setup.sh --all
```

---

## Package Management

CLI dependencies and GUI applications are managed declaratively via [Brewfile](file:///home/brianb/home-settings/macos/Brewfile).

To install or sync packages manually:
```bash
brew bundle --file=macos/Brewfile
```
