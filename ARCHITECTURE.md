# NetBox Offline Installer - Architecture

**Version:** 0.0.1
**Last Updated:** 2026-01-11

---

## Table of Contents

1. [Overview](#overview)
2. [Design Principles](#design-principles)
3. [System Architecture](#system-architecture)
4. [Module Structure](#module-structure)
5. [Data Flow](#data-flow)
6. [Configuration Management](#configuration-management)
7. [Security Architecture](#security-architecture)
8. [Logging & Auditing](#logging--auditing)
9. [Backup System](#backup-system)
10. [OS-Specific Handling](#os-specific-handling)
11. [Extension Points](#extension-points)

---

## Overview

The NetBox Offline Installer is a comprehensive, modular bash-based system designed for deploying and managing NetBox Community Edition in air-gapped, STIG-hardened RHEL environments. The architecture emphasizes security, reliability, and maintainability through clear separation of concerns and defensive programming practices.

### Key Characteristics

- **Language:** Pure bash (POSIX-compliant where possible)
- **Target Platforms:** RHEL 8.10, RHEL 9.x
- **Deployment Model:** Two-phase (online build → offline deployment)
- **Lines of Code:** ~11,000 across 22 files
- **Modules:** 11 library modules + main orchestrator

---

## Design Principles

### 1. **Security First**
- Never store passwords in plaintext (files or logs)
- Cryptographically secure password generation
- Automatic log sanitization
- Defense-in-depth with SELinux and FAPolicyD
- Least privilege execution model

### 2. **Air-Gapped Operation**
- Complete dependency bundling (Python wheels + RPMs)
- No internet connectivity required after build
- Self-contained package validation
- Offline repository management

### 3. **Modular Architecture**
- Single responsibility per module
- Clear interfaces between components
- Minimal coupling, high cohesion
- Easy to test and maintain individual modules

### 4. **Defensive Programming**
- Comprehensive error checking (`set -euo pipefail`)
- Input validation at every boundary
- Safe defaults, fail-safe behavior
- Atomic operations with rollback capabilities

### 5. **Observability**
- Structured, syslog-compliant logging
- Real-time progress feedback
- Comprehensive audit trail
- Diagnostic utilities

### 6. **User Experience**
- Clean, professional console output
- Contextual progress indicators
- Clear error messages with recovery instructions
- Both interactive and silent modes

---

## System Architecture

### High-Level Component Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    NetBox Offline Installer                 │
│                                                             │
│  ┌────────────────────────────────────────────────────────┐ │
│  │         Main Orchestrator (netbox-installer.sh)        │ │
│  │  - Command routing                                     │ │
│  │  - Module loading                                      │ │
│  │  - Environment setup                                   │ │
│  └────────────┬──────────────────────────┬────────────────┘ │
│               │                          │                  │
│  ┌────────────▼──────────┐   ┌───────────▼─────────────┐    │
│  │   Core Modules        │   │   Lifecycle Modules     │    │
│  │  - common.sh          │   │  - build.sh             │    │
│  │  - logging.sh         │   │  - install.sh           │    │
│  │  - validation.sh      │   │  - update.sh            │    │
│  │  - credentials.sh     │   │  - rollback.sh          │    │
│  │                       │   │  - uninstall.sh         │    │
│  └───────────────────────┘   └─────────────────────────┘    │
│                                                             │
│  ┌────────────────────────┐   ┌─────────────────────────┐   │
│  │  Security Modules      │   │  Support Modules        │   │
│  │  - security.sh         │   │  - vm-snapshot.sh       │   │
│  │    - SELinux           │   │  - stig-assessment.sh   │   │
│  │    - FAPolicyD         │   │                         │   │
│  │    - Permissions       │   │                         │   │
│  └────────────────────────┘   └─────────────────────────┘   │
│                                                             │
│  ┌────────────────────────────────────────────────────────┐ │
│  │              Configuration & Templates                 │ │
│  │  - config/defaults.conf                                │ │
│  │  - config/install.conf.example                         │ │
│  │  - templates/*.j2 (systemd, nginx, gunicorn, netbox)   │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                             │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                    Utilities                           │ │
│  │  - utils/validate-package.sh                           │ │
│  │  - utils/cleanup-test-env.sh                           │ │
│  │  - utils/check-superuser.sh                            │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Deployment Architecture

```
┌─────────────────────┐         ┌──────────────────────┐
│  ONLINE SYSTEM      │         │  OFFLINE SYSTEM      │
│  (Build Phase)      │         │  (Deploy Phase)      │
│                     │         │                      │
│  ┌───────────────┐  │         │  ┌────────────────┐  │
│  │ Build Module  │  │  Package│  │ Install Module │  │
│  │               │──┼────────►│  │                │  │
│  │ - Download    │  │ Transfer│  │ - Validate     │  │
│  │ - Bundle      │  │         │  │ - Extract      │  │
│  │ - Package     │  │         │  │ - Configure    │  │
│  └───────┬───────┘  │         │  │ - Deploy       │  │
│          │          │         │  └────────┬───────┘  │
│  ┌───────▼───────┐  │         │  ┌────────▼───────┐  │
│  │ Package       │  │         │  │ Running NetBox │  │
│  │ .tar.gz       │  │         │  │                │  │
│  │ ~200-500MB    │  │         │  │ + PostgreSQL   │  │
│  └───────────────┘  │         │  │ + Redis        │  │
│                     │         │  │ + Nginx        │  │
└─────────────────────┘         │  └────────────────┘  │
                                └──────────────────────┘
```

---

## Module Structure

### Core Modules

#### `lib/common.sh` (Shared Utilities)
**Responsibilities:**
- OS version detection and validation
- RHEL version parsing (`get_rhel_full_version()`)
- Package OS matching validation
- DVD repository auto-detection
- Stale repository cleanup
- Version comparison utilities
- Common helper functions

**Key Functions:**
- `detect_rhel_version()` - Detect RHEL major version (8, 9, 10)
- `validate_package_os_match()` - Ensure package matches target OS
- `setup_dvd_repo()` - Configure local DVD repository
- `cleanup_stale_repos()` - Remove orphaned repository configurations

**Dependencies:** None (base module)

---

#### `lib/logging.sh` (Logging Framework)
**Responsibilities:**
- Syslog-compliant log formatting
- Multi-destination logging (file + console)
- Log level filtering (DEBUG, INFO, WARN, ERROR, SUCCESS)
- Color-coded console output
- Log sanitization (password redaction)
- Session tracking

**Key Functions:**
- `log_debug()`, `log_info()`, `log_warn()`, `log_error()`, `log_success()`
- `log_session_start()`, `log_session_end()`
- `sanitize_log_output()` - Remove sensitive data from logs

**Log Format:**
```
2026-01-11T12:00:00-05:00 hostname netbox-installer[1234]: INFO Message here
```

**Dependencies:** None (base module)

---

#### `lib/validation.sh` (Pre-flight Checks)
**Responsibilities:**
- System requirement validation
- Root privilege verification
- Disk space checks
- Package integrity verification
- Network connectivity tests (build phase only)
- SELinux/FAPolicyD detection

**Key Functions:**
- `validate_root_privileges()` - Ensure running as root
- `validate_disk_space()` - Check minimum free space
- `validate_package_integrity()` - Verify checksums and structure
- `validate_dependencies()` - Check required system packages

**Dependencies:** `common.sh`, `logging.sh`

---

#### `lib/credentials.sh` (Credential Management)
**Responsibilities:**
- Secure password generation (cryptographically random)
- Interactive password prompting with asterisk feedback
- Configuration token processing (`<generate>`, `<prompt>`)
- Password validation (minimum length, complexity)
- Credential extraction from configuration files

**Key Functions:**
- `generate_password()` - Create strong random passwords
- `prompt_password()` - Interactive password input with masking
- `process_config_token()` - Handle `<generate>` and `<prompt>` tokens
- `extract_db_credentials()` - Parse configuration.py for database passwords

**Security Features:**
- Never logs passwords (sanitization in logging module)
- Uses `/dev/urandom` for randomness
- Python `secrets` module for SECRET_KEY
- In-memory only (no plaintext files)

**Dependencies:** `common.sh`, `logging.sh`

---

### Lifecycle Modules

#### `lib/build.sh` (Package Builder)
**Responsibilities:**
- Offline package creation
- Python wheel collection (pip download)
- RPM package download (yumdownloader)
- OS-specific package selection (RHEL 8/9/10 differences)
- Python version enforcement (prevents version drift)
- Manifest generation
- Package compression and checksumming

**Build Process:**
1. Detect RHEL version and set Python/PostgreSQL targets
2. Create build workspace
3. Download Python wheels (105 packages for NetBox)
4. Download RPM dependencies (120 for RHEL 8, 103 for RHEL 9)
5. Generate manifest with OS/Python/PostgreSQL versions
6. Create tarball with structure validation
7. Generate SHA256 checksum

**Key Functions:**
- `collect_python_wheels()` - Download pip packages with version enforcement
- `collect_rpm_packages()` - Download system dependencies
- `generate_manifest()` - Create package metadata
- `create_package_archive()` - Compress and checksum

**Package Structure:**
```
netbox-offline-rhel9-v4.4.9/
├── netbox-installer.sh
├── lib/                      # All library modules
├── config/                   # Configuration files
├── templates/                # File templates
├── utils/                    # Utilities
├── packages/
│   ├── python/              # Python wheels (105 .whl files)
│   ├── rpms/                # RPM packages (103 .rpm files)
│   └── netbox-4.4.9.tar.gz  # NetBox source
└── MANIFEST.txt             # Package metadata
```

**Dependencies:** `common.sh`, `logging.sh`, `validation.sh`

---

#### `lib/install.sh` (Installation Module)
**Responsibilities:**
- NetBox installation on air-gapped systems
- PostgreSQL setup (local or remote)
- Python virtual environment creation
- Database migrations
- Static file collection
- Service configuration (systemd)
- Nginx reverse proxy setup
- Initial backup creation

**Installation Workflow:**
1. Pre-flight validation (OS match, disk space, prerequisites)
2. Extract offline package
3. Install RPM dependencies from local cache
4. Configure PostgreSQL (if local mode)
5. Create NetBox system user and directories
6. Create Python virtual environment (with version enforcement)
7. Install Python dependencies from wheels
8. Generate NetBox configuration (configuration.py)
9. Run database migrations
10. Create superuser account
11. Collect static files
12. Configure and start services
13. Apply security hardening (SELinux, FAPolicyD, permissions)
14. Create initial backup
15. Verify installation health

**Key Functions:**
- `install_rpm_dependencies()` - Install from local RPM cache
- `setup_postgresql_local()` - Configure local database
- `create_virtual_environment()` - Python venv with version matching
- `run_database_migrations()` - Apply Django schema
- `create_superuser()` - Interactive admin account creation
- `configure_services()` - Systemd unit files
- `configure_nginx()` - Reverse proxy with SSL support

**RHEL 8-Specific Handling:**
- Nginx `default_server` directive removal (Fix #21)
- Python 3.11 enforcement (Fix #23)

**Dependencies:** `common.sh`, `logging.sh`, `validation.sh`, `credentials.sh`, `security.sh`

---

#### `lib/update.sh` (Update Module)
**Responsibilities:**
- NetBox version upgrades
- Pre-update backup creation
- Python dependency updates (--force-reinstall)
- Configuration preservation during updates
- Database schema migrations
- Static file updates
- Service restart coordination
- Rollback on failure

**Update Workflow:**
1. Detect currently installed version (from release.yaml)
2. Validate new package version
3. Create pre-update backup
4. Stop NetBox services
5. Update Python dependencies from new wheels
6. Replace NetBox application files (preserve configuration)
7. Run database migrations
8. Collect new static files
9. Restart services
10. Verify update success
11. Clean up temporary files

**Key Functions:**
- `detect_installed_version()` - Read from /opt/netbox/netbox/release.yaml
- `create_preupdate_backup()` - Automatic safety backup
- `update_python_dependencies()` - pip install --upgrade --force-reinstall
- `preserve_configuration()` - Backup and restore configuration.py
- `verify_update()` - Post-update health checks

**Configuration Preservation (Fix #34):**
- Backup configuration.py to temp location OUTSIDE deleted directory
- Delete old NetBox files
- Extract new NetBox version
- Restore backed-up configuration
- Clean up temporary backup file

**Dependencies:** `common.sh`, `logging.sh`, `validation.sh`, `rollback.sh`

---

#### `lib/rollback.sh` (Backup & Restore Module)
**Responsibilities:**
- Manual and automatic backup creation
- Database dump with authentication handling
- Backup retention policy (keeps last N backups)
- Backup listing with metadata display
- Full system restoration
- Database drop/recreate/restore
- Source backup protection during rollback

**Backup Components:**
- **Database:** PostgreSQL dump (compressed .sql.gz)
- **Installation:** Complete /opt/netbox directory (tarball)
- **Configuration:** NetBox configuration.py
- **Media:** User-uploaded files
- **Metadata:** Version, timestamp, size, checksums

**Backup Workflow:**
1. Generate backup directory with timestamp
2. Extract database password from configuration.py (Fix #35)
3. Set backup directory permissions (Fix #44, #46)
4. Dump PostgreSQL database as netbox user (Fix #43, #47)
5. Archive installation directory
6. Generate metadata file
7. Enforce retention policy (delete old backups)

**Restore Workflow:**
1. Validate backup existence and integrity
2. Create pre-rollback safety backup
3. Stop NetBox services
4. Drop existing database
5. Recreate database
6. Restore database from dump (using .pgpass file)
7. Extract installation tarball
8. Set file permissions with context label (Fix #28)
9. Restart services
10. Verify restoration success

**Database Authentication (Fixes #43, #44, #46, #47):**
```bash
# Create temporary .pgpass file for password-less authentication
echo "$db_host:$db_port:$db_name:$db_user:$db_password" > /tmp/.pgpass.$$
chmod 600 /tmp/.pgpass.$$
chown netbox:netbox /tmp/.pgpass.$$

# Run pg_dump as netbox user with IPv4 (not IPv6 ident auth)
sudo -u netbox bash -c "cd /tmp && PGPASSFILE=/tmp/.pgpass.$$ \
  pg_dump -h 127.0.0.1 -p $db_port -U $db_user -d $db_name -F p -f $dump_file"

# Clean up
rm -f /tmp/.pgpass.$$
```

**Retention Policy:**
- Default: Keep last 3 backups
- Configurable via `BACKUP_RETENTION` in install.conf
- Source backup protected during rollback (Fix #42)
- Sorted by timestamp, oldest deleted first

**Key Functions:**
- `create_backup()` - Manual backup creation
- `backup_database()` - PostgreSQL dump with authentication
- `restore_database()` - Database drop/recreate/restore
- `list_backups()` - Display backups with metadata
- `perform_rollback()` - Full system restoration
- `enforce_retention_policy()` - Delete old backups

**Dependencies:** `common.sh`, `logging.sh`, `credentials.sh`, `security.sh`

---

#### `lib/uninstall.sh` (Uninstall Module)
**Responsibilities:**
- Complete NetBox removal
- Service stopping and disabling
- Database deletion
- File system cleanup
- User/group removal
- SELinux context cleanup
- FAPolicyD rule removal
- Optional final backup before removal

**Uninstall Workflow:**
1. Offer to create final backup (optional)
2. Stop and disable systemd services
3. Remove systemd unit files
4. Drop PostgreSQL database and user
5. Remove installation directory (/opt/netbox)
6. Remove system user (netbox)
7. Remove Nginx configuration
8. Clean SELinux contexts and rules
9. Clean FAPolicyD trust rules
10. Ask to delete backups (with confirmation)

**Safety Features:**
- Interactive confirmation required
- Backup offer before destructive operations
- Preserves PostgreSQL, Redis, Nginx services (may be shared)
- Clear warnings about data loss

**Dependencies:** `common.sh`, `logging.sh`, `security.sh`, `rollback.sh`

---

### Security Modules

#### `lib/security.sh` (Security Hardening)
**Responsibilities:**
- SELinux policy detection and configuration
- FAPolicyD trust rule management
- File permission hardening
- System user/group creation
- Ownership enforcement
- SSL/TLS certificate generation

**SELinux Configuration:**
- Automatic policy detection (even if disabled - future-proofing)
- File context application (httpd_sys_content_t, etc.)
- Port labeling (8001/tcp → netbox_port_t)
- Boolean configuration (httpd_can_network_connect)
- Policy persistence across reboots

**FAPolicyD Integration:**
- Automatic trust rule creation in /etc/fapolicyd/rules.d/50-netbox.rules
- Python interpreter whitelisting
- Virtual environment path registration
- "Already trusted" handling (not an error - Fix #17)
- Service restart (not reload - Fix #17)

**Permission Hardening:**
- Directories: 755 (readable, executable by others)
- Files: 644 (readable by others, writable by owner)
- Owner: netbox:netbox
- Real-time progress display (Fix #15)

**System User Creation (Fixes #6, #7):**
```bash
# Handle 4 scenarios:
if user_exists && group_exists && user_in_group; then
    skip_creation
elif user_exists && !user_in_group; then
    usermod -a -G netbox netbox
elif !user_exists && group_exists; then
    useradd -g netbox -r -s /bin/bash -d /opt/netbox netbox
else
    useradd -r -s /bin/bash -d /opt/netbox netbox
fi
```

**Key Functions:**
- `configure_selinux()` - Apply SELinux policies
- `configure_fapolicyd()` - Trust rule management
- `set_secure_permissions()` - Recursive permission hardening with context
- `create_netbox_user()` - System user with group conflict handling
- `generate_self_signed_cert()` - SSL/TLS certificate creation

**Dependencies:** `common.sh`, `logging.sh`

---

### Support Modules

#### `lib/vm-snapshot.sh` (VM Snapshot Integration)
**Responsibilities:**
- VM platform detection (VMware, XCP-ng, KVM, VirtualBox)
- Automated snapshot creation (XCP-ng via Xen Orchestra API)
- Manual snapshot instructions (VMware, KVM, VirtualBox)
- VM UUID detection from guest OS
- SSL/TLS handling (insecure mode or CA bundle)

**Platform Detection:**
- Uses `systemd-detect-virt`, `dmidecode`, `/sys/class/dmi` checks
- Detects: VMware ESXi, XCP-ng, QEMU/KVM, VirtualBox, physical hardware
- **Known Issue:** XCP-ng may be misdetected as VMware (Fix #53 queued)

**XCP-ng Automated Snapshots:**
```bash
# Configuration in install.conf:
VM_SNAPSHOT_ENABLED="yes"
XO_API_URL="https://xo.example.com"
XO_API_TOKEN="your-authentication-token"
XO_API_INSECURE_SSL="yes"  # or provide CA bundle
```

**Snapshot Workflow:**
1. Detect VM platform
2. Extract VM UUID from guest OS
3. Create snapshot via Xen Orchestra REST API
4. Verify snapshot creation
5. Log snapshot ID for reference

**Failure Handling:**
- Warnings only (non-fatal - Fix #52)
- Provides manual instructions if automated fails
- Continues installation/update even if snapshot fails

**Key Functions:**
- `detect_vm_platform()` - Identify hypervisor type
- `get_vm_uuid()` - Extract VM identifier
- `create_vm_snapshot()` - Automated snapshot (XCP-ng)
- `create_vm_snapshot_safe()` - Wrapper with error handling

**Dependencies:** `common.sh`, `logging.sh`

---

#### `lib/stig-assessment.sh` (STIG Compliance)
**Responsibilities:**
- Evaluate-STIG integration (optional)
- Baseline scan before build
- Compliance scan after installation
- Before/after comparison reports
- Report storage and management

**STIG Workflow:**
1. Detect Evaluate-STIG installation
2. Run baseline scan (before package build)
3. Store baseline results
4. Run compliance scan (after NetBox installation)
5. Generate comparison report
6. Store reports in /var/backup/netbox-offline-installer/stig-reports/

**Key Functions:**
- `detect_stig_scanner()` - Find Evaluate-STIG
- `run_baseline_scan()` - Pre-build STIG assessment
- `run_compliance_scan()` - Post-install STIG assessment
- `generate_comparison_report()` - Delta analysis

**Important:** Evaluate-STIG is **NOT** bundled due to licensing restrictions. Users must download separately from https://public.cyber.mil/stigs/

**Dependencies:** `common.sh`, `logging.sh`

---

## Data Flow

### Build Process (Online → Offline Package)

```
┌─────────────────────────────────────────────────────────────────┐
│                         BUILD PHASE                             │
│                    (Internet-Connected)                         │
│                                                                 │
│  1. Detect RHEL Version                                         │
│     ├─ Parse /etc/redhat-release                                │
│     ├─ Determine Python target (3.11 for RHEL 8/9)              │
│     └─ Determine PostgreSQL target (15 for RHEL 8/9)            │
│                                                                 │
│  2. Create Build Workspace                                      │
│     ├─ /var/tmp/netbox-build-XXXXXX                             │
│     └─ Directory structure (packages/python, packages/rpms)     │
│                                                                 │
│  3. Download Python Wheels (pip download)                       │
│     ├─ netbox==4.4.9                                            │
│     ├─ 104 dependencies                                         │
│     ├─ Target Python 3.11 enforced (RHEL 8/9)                   │
│     └─ Total: 105 .whl files (~50MB)                            │
│                                                                 │
│  4. Download RPM Packages (yumdownloader)                       │
│     ├─ PostgreSQL 15 (postgresql15-server, etc.)                │
│     ├─ Python 3.11 (python3.11, python3.11-libs)                │
│     ├─ Nginx, Redis, dependencies                               │
│     ├─ RHEL 8: 120 RPMs (~150MB)                                │
│     └─ RHEL 9: 103 RPMs (~140MB)                                │
│                                                                 │
│  5. Download NetBox Source                                      │
│     ├─ https://github.com/netbox-community/netbox/archive/...   │
│     └─ netbox-4.4.9.tar.gz (~10MB)                              │
│                                                                 │
│  6. Generate Manifest                                           │
│     ├─ NetBox Version: 4.4.9                                    │
│     ├─ RHEL Version: 9                                          │
│     ├─ RHEL Full Version: 9.6                                   │
│     ├─ Python Version: 3.11                                     │
│     ├─ PostgreSQL Version: 15                                   │
│     ├─ Build Date: 2026-01-11T12:00:00-05:00                    │
│     └─ Package checksums                                        │
│                                                                 │
│  7. Create Archive                                              │
│     ├─ tar -czf netbox-offline-rhel9-v4.4.9.tar.gz ...          │
│     ├─ Size: ~191MB (RHEL 9), ~203MB (RHEL 8)                   │
│     └─ SHA256: <checksum>                                       │
│                                                                 │
│  8. Output                                                      │
│     └─ ./dist/netbox-offline-rhel9-v4.4.9.tar.gz                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
         │
         │ Transfer to air-gapped network
         │ (USB, internal network, etc.)
         ▼
┌─────────────────────────────────────────────────────────────────┐
│                      OFFLINE SYSTEM                             │
│                   (No Internet Access)                          │
│                                                                 │
│  Ready for installation (see Installation Process below)        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Installation Process (Offline Package → Deployed NetBox)

```
┌─────────────────────────────────────────────────────────────────┐
│                    INSTALLATION PHASE                           │
│                                                                 │
│  1. Pre-flight Validation                                       │
│     ├─ Root privileges check                                    │
│     ├─ RHEL version detection                                   │
│     ├─ Package OS match validation (RHEL 8 pkg → RHEL 8 sys)    │
│     ├─ Disk space check (5GB minimum)                           │
│     └─ Python version extraction from manifest                  │
│                                                                 │
│  2. Extract Package                                             │
│     └─ tar -xzf netbox-offline-rhel9-v4.4.9.tar.gz              │
│                                                                 │
│  3. Install RPM Dependencies (from local cache)                 │
│     ├─ rpm -Uvh packages/rpms/*.rpm                             │
│     ├─ PostgreSQL 15, Python 3.11, Nginx, Redis                 │
│     └─ Output redirected to log (Fix #19, #22)                  │
│                                                                 │
│  4. Configure PostgreSQL (if DB_MODE="local")                   │
│     ├─ Initialize database cluster                              │
│     ├─ Start postgresql service                                 │
│     ├─ Create netbox database                                   │
│     ├─ Create netbox user                                       │
│     └─ Configure pg_hba.conf (md5 auth for IPv4)                │
│                                                                 │
│  5. Create System User (Handle group conflicts - Fix #6, #7)    │
│     ├─ Check if netbox group exists (created by PostgreSQL)     │
│     ├─ Create netbox user with appropriate flags                │
│     └─ Set ownership of /opt/netbox                             │
│                                                                 │
│  6. Extract NetBox Source                                       │
│     ├─ tar -xzf packages/netbox-4.4.9.tar.gz -C /opt/           │
│     └─ mv /opt/netbox-4.4.9 /opt/netbox                         │
│                                                                 │
│  7. Create Virtual Environment (with version enforcement)       │
│     ├─ Python version from manifest: 3.11                       │
│     ├─ python3.11 -m venv /opt/netbox/venv                      │
│     └─ Validate venv Python matches manifest (Fix #26)          │
│                                                                 │
│  8. Install Python Dependencies (from local wheels)             │
│     ├─ source /opt/netbox/venv/bin/activate                     │
│     ├─ pip install --no-index --find-links=packages/python ...  │
│     ├─ 105 packages installed                                   │
│     └─ Output redirected to log (Fix #37)                       │
│                                                                 │
│  9. Generate Configuration                                      │
│     ├─ Process tokens: <generate>, <prompt>                     │
│     ├─ Auto-detect ALLOWED_HOSTS (Fix #2)                       │
│     ├─ Generate SECRET_KEY (cryptographically random)           │
│     ├─ Set database credentials                                 │
│     └─ Write /opt/netbox/netbox/netbox/configuration.py         │
│                                                                 │
│ 10. Run Database Migrations                                     │
│     ├─ ./manage.py migrate (real-time progress - Fix #11)       │
│     ├─ 202+ migrations applied                                  │
│     ├─ Output streamed to console (Fix #11)                     │
│     └─ Exit code validated (Fix #8)                             │
│                                                                 │
│ 11. Create Superuser (prompted at start - Fix #27)              │
│     ├─ DJANGO_SUPERUSER_PASSWORD from environment               │
│     ├─ ./manage.py createsuperuser --noinput                    │
│     └─ Handle "already exists" gracefully (Fix #3)              │
│                                                                 │
│ 12. Collect Static Files                                        │
│     ├─ ./manage.py collectstatic --noinput                      │
│     └─ Output redirected to log (Fix #50)                       │
│                                                                 │
│ 13. Configure Services                                          │
│     ├─ Generate systemd units from templates                    │
│     │   ├─ netbox.service (Gunicorn)                            │
│     │   └─ netbox-rq.service (Request Queue)                    │
│     ├─ Enable services                                          │
│     └─ Output redirected to log (Fix #19)                       │
│                                                                 │
│ 14. Configure Nginx                                             │
│     ├─ Generate reverse proxy config from template              │
│     ├─ RHEL 8: Remove default_server directive (Fix #21)        │
│     ├─ SSL/TLS setup (self-signed or provided)                  │
│     ├─ Test configuration: nginx -t                             │
│     └─ Start nginx service                                      │
│                                                                 │
│ 15. Apply Security Hardening (context: "NetBox Installation")   │
│     ├─ Configure SELinux contexts (Fix #16)                     │
│     ├─ Configure FAPolicyD trust rules (Fix #17)                │
│     ├─ Set file permissions (Fix #15 - progress display)        │
│     │   ├─ Directories: 755                                     │
│     │   ├─ Files: 644                                           │
│     │   └─ Owner: netbox:netbox                                 │
│     └─ Output with component context (Fix #28)                  │
│                                                                 │
│ 16. Start NetBox Services                                       │
│     ├─ systemctl start netbox netbox-rq                         │
│     ├─ Verify service status (Fix #14)                          │
│     └─ Test HTTP connectivity                                   │
│                                                                 │
│ 17. Create Initial Backup                                       │
│     └─ backup-YYYYMMDD-HHMMSS-initial                           │
│                                                                 │
│ 18. Display Success Message                                     │
│     ├─ Show actual access URLs (Fix #12, #13)                   │
│     ├─ Show service statuses (Fix #14)                          │
│     └─ Provide next steps                                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Update Process (Version A → Version B)

```
┌─────────────────────────────────────────────────────────────────┐
│                       UPDATE PHASE                              │
│                                                                 │
│  1. Detect Current Version                                      │
│     └─ Read /opt/netbox/netbox/release.yaml (Fix #30)           │
│        ├─ version: "4.4.8"                                      │
│        └─ Validated format (Fix #32)                            │
│                                                                 │
│  2. Validate New Package                                        │
│     ├─ Extract version from new package                         │
│     ├─ Version: "4.4.9"                                         │
│     └─ Confirm upgrade path (4.4.8 → 4.4.9 = valid)             │
│                                                                 │
│  3. Create Pre-Update Backup                                    │
│     ├─ backup-YYYYMMDD-HHMMSS-pre-update                        │
│     ├─ Database dump (Fix #43, #47)                             │
│     ├─ Installation archive                                     │
│     └─ Protected from retention during rollback (Fix #42)       │
│                                                                 │
│  4. Stop NetBox Services                                        │
│     └─ systemctl stop netbox netbox-rq                          │
│                                                                 │
│  5. Update Python Dependencies                                  │
│     ├─ source /opt/netbox/venv/bin/activate                     │
│     ├─ pip install --upgrade --force-reinstall ...              │
│     │   └─ --force-reinstall prevents ImportError (Fix #51)     │
│     ├─ 105 packages updated from new wheels                     │
│     └─ Output redirected to log (Fix #37)                       │
│                                                                 │
│  6. Backup Configuration (outside deletion path - Fix #34)      │
│     └─ cp configuration.py /opt/netbox/configuration.py.backup  │
│                                                                 │
│  7. Replace NetBox Files                                        │
│     ├─ rm -rf /opt/netbox/netbox                                │
│     ├─ tar -xzf new-netbox.tar.gz                               │
│     └─ mv netbox-4.4.9 /opt/netbox/netbox                       │
│                                                                 │
│  8. Restore Configuration (Fix #34)                             │
│     ├─ cp /opt/netbox/configuration.py.backup ...               │
│     │   /opt/netbox/netbox/netbox/configuration.py              │
│     └─ rm /opt/netbox/configuration.py.backup                   │
│                                                                 │
│  9. Run Database Migrations                                     │
│     ├─ ./manage.py migrate                                      │
│     ├─ Apply schema changes (4.4.8 → 4.4.9)                     │
│     └─ Output redirected to log (Fix #50)                       │
│                                                                 │
│ 10. Collect New Static Files                                    │
│     ├─ ./manage.py collectstatic --noinput                      │
│     └─ Output redirected to log (Fix #50)                       │
│                                                                 │
│ 11. Set Permissions (context: "NetBox Update" - Fix #28)        │
│     └─ Reapply ownership and permissions                        │
│                                                                 │
│ 12. Restart Services                                            │
│     └─ systemctl start netbox netbox-rq                         │
│                                                                 │
│ 13. Verify Update                                               │
│     ├─ Check service status                                     │
│     ├─ Test HTTP connectivity                                   │
│     └─ Confirm version from release.yaml                        │
│                                                                 │
│ 14. Display Success Message                                     │
│     └─ Show rollback command with correct syntax (Fix #48)      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Rollback Process (Backup → Restoration)

```
┌─────────────────────────────────────────────────────────────────┐
│                      ROLLBACK PHASE                             │
│                                                                 │
│  1. List Available Backups                                      │
│     ├─ Read /var/backup/netbox-offline-installer/               │
│     ├─ Parse metadata (backward-compatible - Fix #41)           │
│     └─ Display with version/date/size                           │
│                                                                 │
│  2. Select Backup (interactive or CLI parameter)                │
│     └─ User selects: backup-20260110-040544-pre-update          │
│                                                                 │
│  3. Validate Backup                                             │
│     ├─ Check directory exists                                   │
│     ├─ Verify database.sql.gz present                           │
│     ├─ Verify installation.tar.gz present                       │
│     └─ Read metadata for version info (Fix #40)                 │
│                                                                 │
│  4. Create Pre-Rollback Safety Backup                           │
│     ├─ backup-YYYYMMDD-HHMMSS-pre-rollback                      │
│     └─ Full backup of current state                             │
│                                                                 │
│  5. Stop NetBox Services                                        │
│     └─ systemctl stop netbox netbox-rq                          │
│                                                                 │
│  6. Drop Existing Database                                      │
│     ├─ sudo -u postgres psql -c "DROP DATABASE netbox;"         │
│     └─ Working directory: /tmp (Fix #47)                        │
│                                                                 │
│  7. Recreate Database                                           │
│     ├─ sudo -u postgres psql -c "CREATE DATABASE netbox ..."    │
│     └─ Working directory: /tmp (Fix #47)                        │
│                                                                 │
│  8. Restore Database (with .pgpass authentication - Fix #47)    │
│     ├─ Create temporary .pgpass file                            │
│     │   ├─ Format: host:port:database:user:password             │
│     │   ├─ Permissions: 600                                     │
│     │   └─ Owner: netbox:netbox                                 │
│     ├─ Restore: gunzip -c database.sql.gz | psql                │
│     │   ├─ Force IPv4: -h 127.0.0.1 (not localhost - Fix #43)   │
│     │   ├─ Run as: sudo -u netbox (Fix #43)                     │
│     │   ├─ Working directory: /tmp (Fix #47)                    │
│     │   └─ Use PGPASSFILE env var (Fix #47 refinement)          │
│     └─ Clean up .pgpass file                                    │
│                                                                 │
│  9. Remove Current Installation                                 │
│     └─ rm -rf /opt/netbox                                       │
│                                                                 │
│ 10. Restore Installation Directory                              │
│     ├─ mkdir -p /opt/netbox                                     │
│     └─ tar -xzf installation.tar.gz -C /opt                     │
│                                                                 │
│ 11. Set Permissions (context: "Rollback Restoration" - Fix #28) │
│     ├─ Directories: 755                                         │
│     ├─ Files: 644                                               │
│     └─ Owner: netbox:netbox                                     │
│                                                                 │
│ 12. Restart Services                                            │
│     └─ systemctl start netbox netbox-rq                         │
│                                                                 │
│ 13. Enforce Retention Policy (protect source - Fix #42)         │
│     ├─ Exclude source backup from deletion                      │
│     ├─ Delete oldest backups beyond retention limit             │
│     └─ Keep last N backups (default: 3)                         │
│                                                                 │
│ 14. Verify Restoration                                          │
│     ├─ Check service status                                     │
│     ├─ Test HTTP connectivity                                   │
│     └─ Confirm version matches backup                           │
│                                                                 │
│ 15. Display Success Message                                     │
│     └─ Show access URLs and service status                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Configuration Management

### Configuration Hierarchy

```
1. Built-in Defaults (config/defaults.conf)
   ↓
2. User Configuration (config/install.conf) - if provided
   ↓
3. Environment Variables (e.g., LOG_LEVEL=DEBUG)
   ↓
4. Command-line Parameters (e.g., -p /path/to/package)
```

### Token System

**Purpose:** Secure credential handling without storing plaintext.

**Supported Tokens:**
- `<generate>` - Auto-generate cryptographically secure password
- `<prompt>` - Prompt user interactively at runtime

**Processing Flow:**
```bash
# In install.conf:
DB_PASSWORD="<generate>"
SUPERUSER_PASSWORD="<prompt>"
SECRET_KEY="<generate>"

# During installation:
DB_PASSWORD=$(process_config_token "<generate>")
  → Calls generate_password()
  → Returns: "X7k!mN@9pQs4&vL2wZ8#yR5tE3uI0oP1" (32 chars)

SUPERUSER_PASSWORD=$(process_config_token "<prompt>")
  → Calls prompt_password("Enter NetBox superuser password")
  → User input with asterisk masking (Fix #4, #9)
  → Returns: user-entered password (validated, not stored)

SECRET_KEY=$(process_config_token "<generate>")
  → Python: import secrets; secrets.token_urlsafe(50)
  → Returns: URL-safe random string (50 chars)
```

**Security:**
- Tokens never stored after processing
- Passwords never logged (sanitized by logging module)
- In-memory only during execution
- Cleared on script exit

### Template Rendering

**Templates (Jinja2-style):**
- `templates/configuration.py.j2` - NetBox configuration
- `templates/gunicorn.py.j2` - Gunicorn WSGI server
- `templates/netbox.service.j2` - NetBox systemd service
- `templates/netbox-rq.service.j2` - Request Queue service
- `templates/nginx-netbox.conf.j2` - Nginx reverse proxy

**Variable Substitution:**
```bash
# Simple replacement (not actual Jinja2, uses sed)
sed "s|{{INSTALL_PATH}}|$INSTALL_PATH|g" template.j2 > output.conf
sed "s|{{DB_NAME}}|$DB_NAME|g" -i output.conf
sed "s|{{DB_USER}}|$DB_USER|g" -i output.conf
# ... etc for all variables
```

**Why not real Jinja2?**
- Avoids external dependencies (Python templating engine)
- Keeps installer pure bash
- Simple variable substitution sufficient for current needs

---

## Security Architecture

### Defense in Depth

```
┌─────────────────────────────────────────────────────────┐
│                   Application Layer                     │
│  - NetBox (Django) with SECRET_KEY                      │
│  - Gunicorn WSGI (127.0.0.1:8001)                       │
│  - Superuser authentication                             │
└────────────┬────────────────────────────────────────────┘
             │
┌────────────▼────────────────────────────────────────────┐
│                   Web Server Layer                      │
│  - Nginx reverse proxy (port 80/443)                    │
│  - SSL/TLS encryption (self-signed or provided)         │
│  - ALLOWED_HOSTS validation                             │
└────────────┬────────────────────────────────────────────┘
             │
┌────────────▼────────────────────────────────────────────┐
│                 Operating System Layer                  │
│  - SELinux enforcing mode                               │
│  - FAPolicyD whitelist enforcement                      │
│  - File permissions (755/644, netbox:netbox)            │
│  - Firewalld (if enabled)                               │
└────────────┬────────────────────────────────────────────┘
             │
┌────────────▼────────────────────────────────────────────┐
│                   Database Layer                        │
│  - PostgreSQL authentication (md5 for IPv4)             │
│  - Database user isolation (netbox user)                │
│  - Connection limiting (local only by default)          │
└─────────────────────────────────────────────────────────┘
```

### Credential Lifecycle

```
┌─────────────────────────────────────────────────────────┐
│               CREDENTIAL GENERATION                     │
│                                                         │
│  User provides:                                         │
│  ├─ DB_PASSWORD="<generate>"                            │
│  ├─ SUPERUSER_PASSWORD="<prompt>"                       │
│  └─ SECRET_KEY="<generate>"                             │
│                                                         │
│  ↓                                                      │
│                                                         │
│  Installer processes:                                   │
│  ├─ DB_PASSWORD = generate_password(32)                 │
│  │   └─ /dev/urandom → "X7k!mN@9pQs4&vL2..."            │
│  ├─ SUPERUSER_PASSWORD = prompt_password()              │
│  │   └─ User input with asterisks → "********"          │
│  └─ SECRET_KEY = python -c "import secrets; ..."        │
│      └─ "RzN3qP8tY5uI0oP1mX7k..."                       │
│                                                         │
│  ↓                                                      │
│                                                         │
│  Stored WHERE:                                          │
│  ├─ DB_PASSWORD → configuration.py (DATABASES dict)     │
│  ├─ SUPERUSER_PASSWORD → Environment var (Django)       │
│  │   └─ NEVER written to disk                           │
│  └─ SECRET_KEY → configuration.py                       │
│                                                         │
│  ↓                                                      │
│                                                         │
│  Logging:                                               │
│  └─ ALL passwords sanitized before logging              │
│      ├─ Regex: password[\"']?\s*[=:]\s*[\"']?([^\"'\s]+)│
│      └─ Replacement: password='***REDACTED***'          │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### SELinux Policy

**File Contexts:**
```bash
# Static files (CSS, JS, images)
/opt/netbox/netbox/static(/.*)?  → httpd_sys_content_t

# Media files (user uploads)
/opt/netbox/netbox/media(/.*)?   → httpd_sys_rw_content_t

# Scripts and executables
/opt/netbox/netbox/manage.py     → httpd_sys_script_exec_t
/opt/netbox/contrib/.*\.sh       → httpd_sys_script_exec_t
```

**Port Labeling:**
```bash
# Allow Gunicorn to bind on port 8001
semanage port -a -t netbox_port_t -p tcp 8001
```

**Booleans:**
```bash
# Allow Nginx to connect to Gunicorn backend
setsebool -P httpd_can_network_connect 1
```

**Verification:**
```bash
ls -Z /opt/netbox/netbox/static/
  → httpd_sys_content_t

ss -tlnp | grep 8001
  → netbox_port_t

getsebool httpd_can_network_connect
  → on
```

### FAPolicyD Trust Rules

**Rule File:** `/etc/fapolicyd/rules.d/50-netbox.rules`

**Trust Patterns:**
```bash
# Trust NetBox installation directory
allow perm=any all : path=/opt/netbox/ trust=1

# Trust Python interpreter
allow perm=execute all : path=/usr/bin/python3.11 trust=1

# Trust virtual environment
allow perm=any all : path=/opt/netbox/venv/ trust=1
```

**Update Process:**
```bash
# After adding rules:
fagenrules --load           # Reload rules
fapolicyd-cli --update      # Update database
systemctl restart fapolicyd # Apply changes
```

---

## Logging & Auditing

### Log Format

**Syslog-Compliant (RFC 3164):**
```
YYYY-MM-DDTHH:MM:SS±ZZ:ZZ hostname program[pid]: LEVEL Message
```

**Example:**
```
2026-01-11T14:32:15-05:00 rh96netbox netbox-installer[12345]: INFO Starting NetBox installation
```

**Components:**
- **Timestamp:** ISO 8601 with timezone
- **Hostname:** From `hostname` command
- **Program:** `netbox-installer`
- **PID:** Current process ID
- **Level:** DEBUG | INFO | WARN | ERROR | SUCCESS
- **Message:** Actual log content

### Multi-Destination Logging

```
                    ┌─────────────┐
                    │ Log Message │
                    └──────┬──────┘
                           │
              ┌────────────▼──────────────┐
              │    Sanitize Passwords     │
              │  (Remove plaintext creds) │
              └────────────┬──────────────┘
                           │
          ┌────────────────▼───────────────┐
          │                                │
    ┌─────▼──────┐                ┌────────▼────────┐
    │  Log File  │                │    Console      │
    │            │                │                 │
    │  /var/log/ │                │  Color-coded    │
    │  netbox-   │                │  Real-time      │
    │  offline-  │                │  User feedback  │
    │  installer.│                │                 │
    │  log       │                │                 │
    └────────────┘                └─────────────────┘
```

### Console Color Coding

```bash
# Colors (Fix #18)
INFO:    Cyan (light blue)    - General information
SUCCESS: Green               - Successful operations
WARN:    Bright Yellow       - Non-fatal warnings
ERROR:   Red                 - Failures and errors
DEBUG:   White               - Diagnostic details
```

### Log Sanitization

**Pattern Matching:**
```bash
# Regex patterns for password detection:
password["']?\s*[=:]\s*["']?([^"'\s]+)
PGPASSWORD=["']?([^"'\s]+)
SECRET_KEY\s*=\s*["']([^"']+)
--password\s+(\S+)
```

**Replacement:**
```bash
password='***REDACTED***'
PGPASSWORD='***REDACTED***'
SECRET_KEY = '***REDACTED***'
--password ***REDACTED***
```

**Implementation:**
```bash
sanitize_log_output() {
    local input="$1"
    # Remove passwords from log output
    echo "$input" | sed -E \
        -e 's/(password["'\'']?\s*[=:]\s*["'\'']?)([^"'\'' \t\n]+)/\1***REDACTED***/gi' \
        -e 's/(PGPASSWORD=)([^ ]+)/\1***REDACTED***/g' \
        -e 's/(SECRET_KEY\s*=\s*["'\''])([^"'\'']+)/\1***REDACTED***/g'
}
```

---

## Backup System

### Backup Structure

```
/var/backup/netbox-offline-installer/
├── backup-20260110-040224-manual/
│   ├── metadata.txt              # Version, timestamp, size, type
│   ├── database/
│   │   └── database.sql.gz       # Compressed PostgreSQL dump (768K)
│   └── installation/
│       └── installation.tar.gz   # Full /opt/netbox archive (106M)
│
├── backup-20260110-040544-pre-update/
│   ├── metadata.txt
│   ├── database/
│   │   └── database.sql.gz
│   └── installation/
│       └── installation.tar.gz
│
└── backup-20260110-042732-pre-rollback/
    ├── metadata.txt
    ├── database/
    │   └── database.sql.gz
    └── installation/
        └── installation.tar.gz
```

### Metadata Format

**File:** `metadata.txt`

```
NetBox Offline Installer - Backup Metadata
===========================================

Backup Date: 2026-01-10 04:02:24 EST
NetBox Version: v4.4.8
Backup Type: manual
Backup Size: 106M

Database:
  Host: localhost
  Port: 5432
  Name: netbox
  User: netbox

Installation:
  Path: /opt/netbox
  Python Version: 3.11
  PostgreSQL Version: 15

Checksums:
  Database: SHA256:abc123...
  Installation: SHA256:def456...
```

### Retention Policy (Fix #42)

**Algorithm:**
```python
def enforce_retention_policy(backups, keep_count, source_backup=None):
    """
    Keep only the last N backups, excluding source backup if specified.

    Args:
        backups: List of backup directories sorted by timestamp
        keep_count: Number of backups to retain (default: 3)
        source_backup: Backup currently being used for rollback (protected)

    Returns:
        List of deleted backups
    """
    # Filter out source backup (rollback source protection)
    if source_backup:
        backups = [b for b in backups if b != source_backup]

    # Sort by timestamp (oldest first)
    sorted_backups = sorted(backups, key=lambda b: b.timestamp)

    # Delete oldest backups beyond retention limit
    to_delete = sorted_backups[:-keep_count] if len(sorted_backups) > keep_count else []

    for backup in to_delete:
        delete_backup(backup)

    return to_delete
```

**Example:**
```bash
# Backups before rollback:
1. backup-20260109-191950-pre-update   (v4.4.8) ← Source for rollback
2. backup-20260109-193344-manual       (v4.4.9)
3. backup-20260109-194043-pre-rollback (v4.4.9)
4. backup-20260109-224037-pre-rollback (v4.4.9)

# Retention policy: keep last 3, exclude source
# Result: Delete #4 (oldest), keep #1 (source), #2, #3
```

---

## OS-Specific Handling

### RHEL 8 vs RHEL 9 Differences

| Feature | RHEL 8 | RHEL 9 | Handling |
|---------|--------|--------|----------|
| **Python Version** | 3.11 (manual) | 3.11 (AppStream) | Version enforcement in build |
| **PostgreSQL** | 15 (module) | 15 (module) | Auto-detection in install |
| **Nginx** | 1.20 (default_server) | 1.24 (no default_server) | Fix #21: Remove directive on RHEL 8 |
| **Package Count** | 120 RPMs | 103 RPMs | Automatic based on OS |
| **Package Size** | 203MB | 191MB | Expected difference |

### Nginx default_server Handling (Fix #21)

**Problem:** RHEL 8's `/etc/nginx/nginx.conf` includes `listen 80 default_server;` which intercepts all HTTP traffic before NetBox virtual host can match.

**RHEL 8 nginx.conf:**
```nginx
server {
    listen       80 default_server;    # ← Intercepts traffic
    listen       [::]:80 default_server;
    server_name  _;
    ...
}
```

**RHEL 9 nginx.conf:**
```nginx
server {
    listen       80;                    # ← No default_server
    listen       [::]:80;
    server_name  _;
    ...
}
```

**Solution (RHEL 8 only):**
```bash
if [[ "$RHEL_VERSION" == "8" ]]; then
    if grep -q "listen.*80.*default_server" /etc/nginx/nginx.conf; then
        sed -i 's/listen       80 default_server;/listen       80;/' /etc/nginx/nginx.conf
        sed -i 's/listen       \[::\]:80 default_server;/listen       [::]:80;/' /etc/nginx/nginx.conf
        nginx -t && systemctl reload nginx
    fi
fi
```

### Python Version Enforcement (Fix #23)

**Problem:** Build system may find newer Python (3.12 from EPEL) but installation requires specific version (3.11 for RHEL 8/9).

**Solution:**
```bash
# In build.sh:
determine_python_version() {
    case "$RHEL_VERSION" in
        8|9)
            echo "3.11"
            ;;
        10)
            echo "3.12"
            ;;
    esac
}

target_python_version=$(determine_python_version)
collect_python_wheels "$netbox_version" "$wheels_dir" "$target_python_version"
```

**Validation:**
```bash
# In collect_python_wheels():
if [[ -n "$target_python_version" ]]; then
    # Only search for exact version
    python_cmd="python${target_python_version}"

    # Validate found version matches target
    found_version=$($python_cmd --version | grep -oP '\d+\.\d+')
    if [[ "$found_version" != "$target_python_version" ]]; then
        error "Python version mismatch"
    fi
fi
```

---

## Extension Points

### Adding New OS Support

**Required Changes:**

1. **Update `lib/common.sh`:**
   ```bash
   detect_rhel_version() {
       case "$full_version" in
           8.*) echo "8" ;;
           9.*) echo "9" ;;
           10.*) echo "10" ;;
           11.*) echo "11" ;;  # ← Add new version
           *) error "Unsupported RHEL version" ;;
       esac
   }
   ```

2. **Update `lib/build.sh`:**
   ```bash
   determine_python_version() {
       case "$RHEL_VERSION" in
           8|9) echo "3.11" ;;
           10) echo "3.12" ;;
           11) echo "3.13" ;;  # ← Add Python target
       esac
   }

   determine_postgresql_version() {
       case "$RHEL_VERSION" in
           8|9) echo "15" ;;
           10) echo "16" ;;
           11) echo "17" ;;    # ← Add PostgreSQL target
       esac
   }
   ```

3. **Add OS-specific fixes in `lib/install.sh`:**
   ```bash
   apply_os_specific_fixes() {
       case "$RHEL_VERSION" in
           8) fix_rhel8_nginx_default_server ;;
           9) : ;;  # No fixes needed
           10) : ;; # No fixes needed
           11) fix_rhel11_specific_issue ;;  # ← New fixes
       esac
   }
   ```

4. **Update documentation:**
   - README.md: Add to Supported Platforms
   - CHANGELOG.md: Document new support
   - CLAUDE.md: Update session notes

### Adding New Features

**Example: Add SSL Certificate Renewal**

1. **Create new module:**
   ```bash
   # lib/ssl-management.sh
   renew_ssl_certificate() {
       # Implementation
   }
   ```

2. **Add to main orchestrator:**
   ```bash
   # netbox-installer.sh
   source "${LIB_DIR}/ssl-management.sh"

   case "$command" in
       renew-ssl)
           renew_ssl_certificate
           ;;
   esac
   ```

3. **Add configuration:**
   ```bash
   # config/defaults.conf
   SSL_RENEW_DAYS="30"  # Renew 30 days before expiry
   ```

4. **Update documentation:**
   - Add to README.md operations list
   - Create Wiki page: SSL-Certificate-Management
   - Update help text in netbox-installer.sh

### Adding New Security Integrations

**Example: Add AppArmor Support**

1. **Create security profile:**
   ```bash
   # lib/security.sh
   configure_apparmor() {
       if ! command -v apparmor_parser &>/dev/null; then
           log_warn "AppArmor not installed"
           return 0
       fi

       # Create profile
       cp templates/netbox-apparmor.profile /etc/apparmor.d/netbox
       apparmor_parser -r /etc/apparmor.d/netbox

       log_success "AppArmor profile applied"
   }
   ```

2. **Call during installation:**
   ```bash
   # lib/install.sh
   log_info "Applying security hardening..."
   configure_selinux
   configure_fapolicyd
   configure_apparmor  # ← New integration
   set_secure_permissions "NetBox Installation"
   ```

3. **Add configuration toggle:**
   ```bash
   # config/defaults.conf
   ENABLE_APPARMOR="auto"  # auto, yes, no
   ```

---

## Conclusion

The NetBox Offline Installer demonstrates a well-architected approach to complex bash-based automation. Key strengths include:

1. **Modular Design** - Clear separation of concerns enables maintainability
2. **Security Focus** - Defense-in-depth with multiple layers of protection
3. **Air-Gapped Operation** - Complete offline capability after initial build
4. **Comprehensive Testing** - 52 fixes validated across RHEL 8 and RHEL 9
5. **User Experience** - Professional presentation with clean output and helpful feedback
6. **Extensibility** - Well-defined extension points for future enhancements

The architecture successfully balances complexity (air-gapped deployment, multi-OS support, security hardening) with usability (interactive mode, automated operations, clear documentation).

---

**For Questions or Contributions:**
- Review this architecture document
- Consult module-specific documentation in code comments
- Check [GitHub Wiki](../../wiki) for detailed guides
- Follow the extension points outlined above

**Version:** 0.0.1
**Last Updated:** 2026-01-11
