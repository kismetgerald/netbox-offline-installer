# Contributing to NetBox Offline Installer

Thank you for your interest in contributing to the NetBox Offline Installer project! We welcome contributions that help expand OS support, add features, fix bugs, and improve documentation.

## Table of Contents

- [Getting Started](#getting-started)
- [Development Environment](#development-environment)
- [How to Contribute](#how-to-contribute)
- [Contribution Guidelines](#contribution-guidelines)
- [Testing Requirements](#testing-requirements)
- [Code Standards](#code-standards)
- [Submitting Changes](#submitting-changes)
- [Priority Areas](#priority-areas)

---

## Getting Started

This project provides offline installation of NetBox Community Edition on RHEL-based systems. While initially developed for secure, air-gapped DoD environments, **we welcome contributions from anyone** who needs reliable NetBox deployment automation.

Before contributing, please:

1. **Read the Documentation**: Familiarize yourself with [README.md](README.md), [ARCHITECTURE.md](ARCHITECTURE.md), and [CHANGELOG.md](CHANGELOG.md)
2. **Understand the Core Design**: Offline-first architecture ensures all dependencies are bundled (no internet required on target systems)
3. **Review Open Issues**: Check existing [issues](../../issues) and [pull requests](../../pulls) to avoid duplication

## Development Environment

### Requirements

- **Build/Test System**: RHEL 8.10, RHEL 9.x, or compatible derivative (Rocky Linux, AlmaLinux)
- **Root Access**: Required for installation and testing
- **VM Environment**: Recommended for testing (VMware, XCP-ng, VirtualBox, KVM)
- **Internet Access**: Build system needs internet connectivity; test system should be air-gapped

### Recommended Setup

```bash
# Development machine (any OS with Git)
git clone https://github.com/your-repo/netbox-offline-installer.git
cd netbox-offline-installer

# Build system (RHEL 8/9 with internet)
# - Use for building offline packages
# - Test build process on target OS version

# Test system (RHEL 8/9 air-gapped)
# - Use for installation testing
# - Should match production environment (STIG-hardened if possible)
```

---

## How to Contribute

### Types of Contributions Welcome

1. **Bug Fixes**
   - Installation failures
   - Configuration errors
   - Service issues
   - Security vulnerabilities

2. **Feature Enhancements**
   - New lifecycle operations
   - Configuration options
   - Integration with external tools
   - Performance improvements

3. **OS Support Expansion**
   - RHEL 10 (when STIG profiles available)
   - Rocky Linux 8/9/10
   - AlmaLinux 8/9/10
   - Oracle Linux 8/9/10

4. **Documentation Improvements**
   - Installation guides
   - Troubleshooting tips
   - Configuration examples
   - Architecture diagrams

5. **Testing & Validation**
   - Test case development
   - Regression testing
   - STIG compliance validation
   - Performance benchmarking

---

## Contribution Guidelines

### Project Goals

All contributions should align with these core principles:

1. **Offline-First**: Must work without internet connectivity on target systems (primary use case)
2. **Production-Ready**: Code must be reliable, tested, and maintainable for enterprise deployments
3. **Security-Focused**: Never compromise security for convenience
4. **Broadly Compatible**: Support diverse environments (STIG-hardened DoD, corporate data centers, home labs, etc.)
5. **Dependency Bundling**: All dependencies packaged offline for reliable deployment

### What We're Looking For

✅ **High Priority**:
- **Operating System Expansion**:
  - RHEL 10 support (awaiting STIG profiles from Red Hat)
  - Rocky Linux 8/9/10 support
  - AlmaLinux 8/9/10 support
  - Oracle Linux 8/9/10 support
  - Debian/Ubuntu support (if offline bundling remains feasible)

- **Database & Language Support**:
  - PostgreSQL 16 support for RHEL 10
  - Python 3.12 support for RHEL 10
  - Remote PostgreSQL configuration improvements
  - Database clustering support

- **Authentication Integration**:
  - LDAP/Active Directory authentication
  - OIDC/SAML authentication (Keycloak, Okta, Azure AD)
  - PAM/SSSD integration

- **Automation & Deployment**:
  - Ansible playbook wrappers
  - Terraform modules
  - CI/CD pipeline integration examples
  - Configuration-as-code templates

- **Enterprise Features**:
  - SSL/TLS certificate automation (Let's Encrypt for online build systems, custom CA for air-gapped)
  - High availability (HA) configuration
  - NetBox plugin installation support
  - Performance tuning automation
  - Backup encryption

✅ **Medium Priority**:
- Monitoring integration (Prometheus, Grafana, Nagios, Zabbix)
- Logging aggregation (ELK, Splunk)
- Disaster recovery procedures
- Multi-site replication
- Custom branding support
- Internationalization (i18n)

✅ **Always Welcome**:
- Bug fixes (any severity)
- Documentation improvements (guides, diagrams, examples)
- Test coverage expansion
- Error handling improvements
- User experience enhancements
- Performance optimizations
- Translations

✅ **Financial Support**:
We welcome financial contributions to support:
- Testing infrastructure (cloud VMs, hardware)
- Development time for major features
- Documentation and training materials
- Community events and workshops

Contact maintainers to discuss sponsorship opportunities.

❌ **Not Currently Aligned**:
- Docker/Kubernetes-only deployments (conflicts with offline-first and STIG requirements, but Docker *supplementary* tools welcome)
- Cloud-specific features requiring vendor APIs (AWS, Azure, GCP - unless offline-compatible)
- Features requiring internet connectivity on target installation systems
- Proprietary/closed-source components

---

## Testing Requirements

All contributions must include testing evidence:

### For Bug Fixes

```bash
# 1. Reproduce the bug
# Document: OS version, NetBox version, error messages, logs

# 2. Apply fix
# Document: Changed files, line numbers

# 3. Test fix
# Document: Test procedure, before/after behavior, logs

# 4. Regression test
# Verify: No new issues introduced
```

### For New Features

```bash
# 1. Build offline package
sudo ./netbox-installer.sh build

# 2. Test installation (fresh install)
sudo ./netbox-installer.sh install -p /path/to/package

# 3. Test feature functionality
# Document: Feature usage, expected behavior, actual behavior

# 4. Test lifecycle operations
# - Update to new version (if applicable)
# - Backup and restore (if applicable)
# - Rollback (if applicable)

# 5. Test on all supported OS versions
# - RHEL 8.10
# - RHEL 9.x
# - Any new OS variants introduced
```

### Testing Checklist

- [ ] Tested on clean system (no previous NetBox installation)
- [ ] Tested on STIG-hardened system (if possible)
- [ ] Tested with SELinux enforcing
- [ ] Tested with FAPolicyD active (RHEL 8/9)
- [ ] All services start successfully
- [ ] Web interface accessible
- [ ] Database connectivity verified
- [ ] Backup/restore tested (if applicable)
- [ ] Update/rollback tested (if applicable)
- [ ] No security warnings or errors
- [ ] Log files reviewed for errors

---

## Code Standards

### Shell Script Standards

```bash
#!/bin/bash
#
# NetBox Offline Installer - Module Name
# Version: 0.0.1
# Description: Brief description of module purpose
#
# Created by: Your Name (your.email@example.com)
# Date Created: YYYY-MM-DD
# Last Updated: YYYY-MM-DD
#

# Use bash strict mode where appropriate
set -euo pipefail

# Function naming: lowercase_with_underscores
function_name() {
    local variable_name="value"

    # Always use logging framework
    log_info "Performing operation..."

    # Error handling
    if ! command_that_might_fail; then
        log_error "Operation failed"
        return 1
    fi

    return 0
}

# Use shellcheck for linting
# Install: dnf install shellcheck
# Run: shellcheck script.sh
```

### Logging Standards

```bash
# Always use logging framework, never echo directly
log_debug "Detailed diagnostic information"
log_info "Normal operational messages"
log_success "Operation completed successfully"  # Use for major milestones
log_warn "Warning: potential issue"
log_error "Error: operation failed"

# Redirect external commands to log file
command >> "$LOG_FILE" 2>&1

# For long operations, provide progress feedback
log_info "Processing 1000 items..."
# ... processing with progress updates ...
log_info "Processed 1000 items successfully"
```

### Security Standards

```bash
# Never log passwords or sensitive data
DB_PASSWORD="$(generate_password 32)"  # Auto-generated
log_info "Database password configured"  # Don't log actual password

# Sanitize logs automatically (handled by logging framework)
# Pattern: password['"]?\s*[=:]\s*['"]?([^'"\s]+)
# Replacement: password='***REDACTED***'

# Use secure file permissions
chmod 600 /path/to/sensitive/file
chown netbox:netbox /path/to/netbox/file

# SELinux contexts
chcon -t httpd_sys_content_t /path/to/static/files

# FAPolicyD trust rules
fapolicyd-cli --file add /path/to/python/executable
```

### Error Handling

```bash
# Check prerequisites
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

# Validate inputs
if [[ -z "${REQUIRED_VAR:-}" ]]; then
    log_error "REQUIRED_VAR is not set"
    return 1
fi

# Use exit codes consistently
# 0 = success
# 1 = general error
# 2 = usage error (invalid arguments)
```

---

## Submitting Changes

### Pull Request Process

1. **Fork the Repository**
   ```bash
   # Fork via GitHub web interface
   git clone https://github.com/your-username/netbox-offline-installer.git
   cd netbox-offline-installer
   git remote add upstream https://github.com/original-repo/netbox-offline-installer.git
   ```

2. **Create a Feature Branch**
   ```bash
   git checkout -b feature/add-rocky-linux-support
   # or
   git checkout -b fix/database-backup-permissions
   ```

3. **Make Your Changes**
   - Follow code standards
   - Update documentation
   - Add tests

4. **Test Thoroughly**
   - Run on clean test system
   - Verify no regressions
   - Document test results

5. **Commit Changes**
   ```bash
   git add .
   git commit -m "Add Rocky Linux 9 support

   - Detect Rocky Linux OS version
   - Handle repository differences
   - Update documentation
   - Tested on Rocky Linux 9.3

   Closes #123"
   ```

6. **Push to Your Fork**
   ```bash
   git push origin feature/add-rocky-linux-support
   ```

7. **Open Pull Request**
   - Provide clear description
   - Reference related issues
   - Include testing evidence
   - Add screenshots/logs if helpful

### Pull Request Template

```markdown
## Description
Brief description of changes

## Motivation
Why is this change needed?

## Changes Made
- File 1: Description of changes
- File 2: Description of changes

## Testing
- [ ] Tested on RHEL 8.10
- [ ] Tested on RHEL 9.x
- [ ] Tested on [New OS variant]
- [ ] Build successful
- [ ] Installation successful
- [ ] All services active
- [ ] Web access verified
- [ ] Backup/restore tested (if applicable)

## Test Evidence
- OS Version: RHEL 9.6
- NetBox Version: 4.4.9
- Test Date: 2026-01-11
- Test Results: All tests passed

Logs:
```
[Paste relevant log excerpts]
```

## Breaking Changes
None / [Description of breaking changes]

## Documentation
- [ ] README.md updated
- [ ] CHANGELOG.md updated
- [ ] ARCHITECTURE.md updated (if applicable)
- [ ] Wiki updated (if applicable)

## Checklist
- [ ] Code follows project style guidelines
- [ ] Self-review completed
- [ ] Comments added for complex logic
- [ ] Documentation updated
- [ ] No new warnings or errors
- [ ] Tested on multiple OS versions
- [ ] Backward compatible (or breaking changes documented)
```

---

## Priority Areas

### Phase 1.6: RHEL-Derivative Support

**Status**: Planned
**Help Wanted**: Yes

We need contributors with access to:
- Rocky Linux 8/9/10 systems
- AlmaLinux 8/9/10 systems
- Oracle Linux 8/9/10 systems

**Challenges**:
- Package bundling differences (e.g., pip separation in AlmaLinux 10)
- Repository availability differences
- STIG/FAPolicyD not shipped by default
- Distribution-specific quirks

### Phase 2.5: Centralized Authentication

**Status**: Planned
**Help Wanted**: Yes

Looking for contributors with expertise in:
- LDAP/Active Directory integration with Django
- OIDC/SAML authentication
- Keycloak configuration
- PAM/SSSD configuration on RHEL

### Phase 3: High Availability

**Status**: Future
**Help Wanted**: Yes

Seeking contributors with experience in:
- PostgreSQL clustering/replication
- Load balancing (HAProxy, Nginx)
- Shared storage (NFS, GlusterFS)
- Keepalived/VRRP

---

## Community

### Communication Channels

- **GitHub Issues**: Bug reports, feature requests, questions
- **GitHub Discussions**: General discussions, ideas, Q&A
- **Pull Requests**: Code contributions, documentation updates

### Code of Conduct

This project adheres to the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

### Recognition

Contributors will be recognized in:
- CHANGELOG.md (for significant contributions)
- Git commit history
- GitHub contributors page

---

## Questions?

If you have questions about contributing:

1. Check existing [documentation](README.md)
2. Search [closed issues](../../issues?q=is%3Aissue+is%3Aclosed)
3. Open a [new discussion](../../discussions/new)
4. Contact the maintainers

---

## License

By contributing to this project, you agree that your contributions will be licensed under the [MIT License](LICENSE.txt).

---

Thank you for contributing to NetBox Offline Installer! Your efforts help organizations deploy NetBox securely in air-gapped environments.
