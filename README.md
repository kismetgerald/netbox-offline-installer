# NetBox Offline Installer

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE.txt)
[![RHEL 8](https://img.shields.io/badge/RHEL-8.10-red.svg)](https://access.redhat.com/products/red-hat-enterprise-linux)
[![RHEL 9](https://img.shields.io/badge/RHEL-9.x-red.svg)](https://access.redhat.com/products/red-hat-enterprise-linux)
[![NetBox](https://img.shields.io/badge/NetBox-4.4.x-blue.svg)](https://github.com/netbox-community/netbox)

Comprehensive offline installation system for NetBox Community Edition on RHEL 8/9 air-gapped networks. Designed for secure, STIG-compliant environments requiring full lifecycle management.

## Features

- **Offline Installation** - Deploy on completely air-gapped networks with all dependencies bundled
- **Full Lifecycle** - Build, install, update, backup, restore, rollback, and uninstall operations
- **Security Hardened** - Automatic SELinux, FAPolicyD, and credential management
- **Audit Logging** - Syslog-compliant logs for RMF/STIG/JSIG compliance
- **Backup/Restore** - Automatic backups with configurable retention policies
- **Database Flexibility** - Local PostgreSQL or remote database support
- **VM Snapshots** - Optional integration with VMware and XCP-ng
- **STIG Assessment** - Optional Evaluate-STIG integration for compliance scanning

## Quick Start

### Building the Package (Online System)

```bash
# On internet-connected RHEL 8/9 system with root access
sudo ./netbox-installer.sh build

# Output: ./dist/netbox-offline-rhel{8|9}-v4.4.9.tar.gz
```

**Important:** Build on RHEL 8 for RHEL 8 targets, RHEL 9 for RHEL 9 targets (binary compatibility).

### Installing NetBox (Offline System)

```bash
# Extract package on air-gapped RHEL 8/9 system
tar -xzf netbox-offline-rhel9-v4.4.9.tar.gz
cd netbox-offline-rhel9-v4.4.9

# Interactive installation
sudo ./netbox-installer.sh install -p .

# Silent installation with configuration file
sudo ./netbox-installer.sh install -c install.conf -p .
```

## System Requirements

**Build System (Online):**
- RHEL 8.10 or RHEL 9.x (must match target version)
- Internet connectivity
- Root privileges
- 5GB+ free disk space

**Target System (Offline):**
- RHEL 8.10 or RHEL 9.x
- 4GB+ RAM (recommended)
- 5GB+ free disk space
- Root privileges

## Supported Platforms

**Production Ready:**
- Red Hat Enterprise Linux 9.x (Recommended)
- Red Hat Enterprise Linux 8.10 (Legacy support - EOL with sunset DISA STIGs)

**Future Support:**
- RHEL 10 (Deferred pending DISA STIG profile availability)
- Rocky Linux 8/9/10 (Planned for Phase 1.6)
- AlmaLinux 8/9/10 (Planned for Phase 1.6)

## Documentation

Comprehensive documentation is available in the [GitHub Wiki](../../wiki):

- **[Installation Guide](../../wiki/Installation-Guide)** - Detailed installation instructions and modes
- **[Configuration Reference](../../wiki/Configuration-Reference)** - All configuration options and tokens
- **[Update & Rollback](../../wiki/Update-and-Rollback)** - Lifecycle management procedures
- **[Backup & Restore](../../wiki/Backup-and-Restore)** - Backup strategies and retention policies
- **[Security Hardening](../../wiki/Security-Hardening)** - SELinux, FAPolicyD, and SSL/TLS configuration
- **[Database Modes](../../wiki/Database-Modes)** - Local vs remote PostgreSQL setup
- **[VM Snapshots](../../wiki/VM-Snapshots)** - VMware and XCP-ng integration
- **[STIG Compliance](../../wiki/STIG-Compliance)** - Evaluate-STIG integration and RMF requirements
- **[Troubleshooting](../../wiki/Troubleshooting)** - Common issues and solutions
- **[API Reference](../../wiki/API-Reference)** - Command-line interface and scripting

## Basic Operations

```bash
# Interactive menu
sudo ./netbox-installer.sh

# Build offline package
sudo ./netbox-installer.sh build

# Install NetBox
sudo ./netbox-installer.sh install -p /path/to/package

# Update to new version
sudo ./netbox-installer.sh update -p /path/to/new-package

# Create manual backup
sudo ./netbox-installer.sh backup

# List available backups
sudo ./netbox-installer.sh list-backups

# Rollback to previous version
sudo ./netbox-installer.sh rollback -b backup-20240115-120000

# Uninstall NetBox
sudo ./netbox-installer.sh uninstall

# Show version
sudo ./netbox-installer.sh version
```

## Configuration

Configuration files are located in `config/`:
- `install.conf.example` - Example configuration with all options documented
- `defaults.conf` - Default values (do not modify)

### Configuration Tokens

Special tokens for secure credential handling:
- `<generate>` - Auto-generate strong passwords
- `<prompt>` - Prompt user at runtime (never stored in plaintext)

Example configuration snippet:

```bash
DB_PASSWORD="<generate>"
SUPERUSER_PASSWORD="<prompt>"
SECRET_KEY="<generate>"
```

See [Configuration Reference](../../wiki/Configuration-Reference) in the Wiki for complete documentation.

## Logging

All operations are logged to `/var/log/netbox-offline-installer.log` in syslog-compliant format. Console output provides color-coded real-time feedback.

Set log level with environment variable:

```bash
LOG_LEVEL="DEBUG" sudo ./netbox-installer.sh install -p /path/to/package
```

Available log levels: `DEBUG`, `INFO`, `WARN`, `ERROR`

## File Structure

```
netbox-offline-installer/
├── netbox-installer.sh              # Main entry point
├── build-netbox-offline-package.sh  # Build-only wrapper
├── lib/                             # Core library modules
│   ├── common.sh
│   ├── logging.sh
│   ├── credentials.sh
│   ├── security.sh
│   ├── vm-snapshot.sh
│   ├── stig-assessment.sh
│   ├── build.sh
│   ├── install.sh
│   ├── update.sh
│   ├── rollback.sh
│   └── uninstall.sh
├── config/                          # Configuration files
│   ├── install.conf.example
│   └── defaults.conf
├── templates/                       # File templates (systemd, nginx, etc.)
├── utils/                           # Diagnostic and helper tools
└── README.md                        # This file
```

## License

This project is licensed under the MIT License - see the [LICENSE.txt](LICENSE.txt) file for details.

NetBox Community Edition is licensed under Apache License 2.0. See the [NetBox repository](https://github.com/netbox-community/netbox/blob/develop/LICENSE.txt) for details.

## Support

**For NetBox itself:**
- Official Documentation: https://docs.netbox.dev/
- Community Discussions: https://github.com/netbox-community/netbox/discussions
- Slack Community: https://netdev.chat/

**For this installer:**
- Check logs first: `sudo cat /var/log/netbox-offline-installer.log`
- Review [Troubleshooting Guide](../../wiki/Troubleshooting) in the Wiki
- Search existing issues in the repository

## Contributing

Contributions are welcome from anyone interested in NetBox deployment automation! We accept:

- **Code contributions**: Bug fixes, features, OS support, integrations
- **Documentation**: Guides, examples, translations, diagrams
- **Testing**: Validation on different OS versions and environments
- **Financial support**: Help fund testing infrastructure and development

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines. While initially developed for air-gapped DoD environments, this project aims to serve any organization needing reliable, offline-capable NetBox installation.

## Version

**NetBox Offline Installer v0.0.1**

Supports NetBox Community Edition 4.4.x on RHEL 8/9.

## Credits

Developed for secure, air-gapped deployment of NetBox on RHEL 8/9 networks with RMF/STIG/JSIG compliance requirements.
