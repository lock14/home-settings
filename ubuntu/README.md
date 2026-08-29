# Ubuntu Setup

Setup automation for **Ubuntu (22.04+ / 24.04+ LTS)** workstations.

The system setup module configures:
- System package updates via APT
- Core developer CLI tools (`git`, `vim`, `curl`, `wget`, `maven`, `mariadb`, `dconf-cli`, `shellcheck`)
- Google Chrome (amd64)
- Modern OpenJDK LTS (`17` or `21`, default: `21`) and alternatives configuration
- Java IDE (IntelliJ IDEA Ultimate/Community, Eclipse, NetBeans, or VS Code) via Snap
- Developer desktop tools (Postman, Slack, VS Code) via Snap

## Usage

```bash
# Run via master setup orchestrator
./setup.sh --os ubuntu --jdk 21 --ide intellij-ultimate

# Or directly via Ubuntu adapter
./ubuntu/ubuntu_18+_setup.sh -j 21 -i intellij-ultimate
```

## Options
- `-j, --jdk`: Active Java LTS version (`17` or `21`, default: `21`). Note: EOL versions (8, 11) are rejected.
- `-i, --ide`: Developer IDE (`intellij`, `intellij-ultimate`, `eclipse`, `netbeans`, `code`, `none`).
