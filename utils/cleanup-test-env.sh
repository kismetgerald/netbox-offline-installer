#!/bin/bash
#
# NetBox Test Environment Cleanup Script
# Version: 0.0.2
# Description: Cleans up failed/partial NetBox installations for testing
#
# Created by: Kismet Agbasi (KismetG17@gmail.com)
# AI Collaborator: Claude Code (integrated with VS Code)
# Date Created: 12/28/2025
# Last Updated: 12/28/2025
#
# Usage:
#   ./cleanup-test-env.sh           # Interactive mode (prompts)
#   ./cleanup-test-env.sh --force   # Force mode (no prompts, removes everything)
#   ./cleanup-test-env.sh -f        # Same as --force
#

set -e

# Parse command line arguments
FORCE_MODE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--force)
            FORCE_MODE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo
            echo "Options:"
            echo "  -f, --force    Force cleanup without prompts (removes everything)"
            echo "  -h, --help     Show this help message"
            echo
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored message
print_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Confirmation prompt (skipped in force mode)
confirm() {
    local prompt="$1"
    local default="${2:-n}"

    # Always return true in force mode
    if [[ "$FORCE_MODE" == true ]]; then
        return 0
    fi

    if [[ "$default" == "y" ]]; then
        read -r -p "$prompt [Y/n]: " response
        response=${response:-y}
    else
        read -r -p "$prompt [y/N]: " response
        response=${response:-n}
    fi

    [[ "$response" =~ ^[Yy]$ ]]
}

# Display header
echo
echo "================================================================================"
echo "                NetBox Test Environment Cleanup"
echo "================================================================================"
echo
if [[ "$FORCE_MODE" == true ]]; then
    print_warn "FORCE MODE ENABLED - All prompts bypassed, removing everything"
else
    print_warn "This script will remove NetBox installation and related components"
fi
echo

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root"
    exit 1
fi

# Default paths
INSTALL_PATH="/opt/netbox"
BACKUP_DIR="/var/backup/netbox-offline-installer"
LOG_FILE="/var/log/netbox-offline-installer.log"

# Dynamically find NetBox offline package files (any version)
PACKAGE_EXTRACT_DIRS=()
PACKAGE_TARBALLS=()

# Find all extracted package directories in /root matching pattern: netbox-offline-rhel*-v*
while IFS= read -r dir; do
    [[ -d "$dir" ]] && PACKAGE_EXTRACT_DIRS+=("$dir")
done < <(find /root -maxdepth 1 -type d -name "netbox-offline-rhel*-v*" 2>/dev/null)

# Find all package tarballs in /root matching pattern: netbox-offline-rhel*-v*.tar.gz
while IFS= read -r tarball; do
    [[ -f "$tarball" ]] && PACKAGE_TARBALLS+=("$tarball")
done < <(find /root -maxdepth 1 -type f -name "netbox-offline-rhel*-v*.tar.gz" 2>/dev/null)

# Display what will be removed
if [[ "$FORCE_MODE" == false ]]; then
    echo "This will remove:"
    echo "  - NetBox services (netbox, netbox-rq)"
    echo "  - NetBox installation directory ($INSTALL_PATH)"
    echo "  - NetBox database and PostgreSQL user"
    echo "  - NetBox system user"
    echo "  - Systemd service files"
    echo "  - Nginx configuration"

    # Display found package directories
    if [[ ${#PACKAGE_EXTRACT_DIRS[@]} -gt 0 ]]; then
        echo "  - Offline package directories:"
        for dir in "${PACKAGE_EXTRACT_DIRS[@]}"; do
            echo "      $dir"
        done
    fi

    # Display found package tarballs
    if [[ ${#PACKAGE_TARBALLS[@]} -gt 0 ]]; then
        echo "  - Offline package tarballs:"
        for tarball in "${PACKAGE_TARBALLS[@]}"; do
            echo "      $tarball"
        done
    fi

    echo "  - PostgreSQL data directory (will prompt separately)"
    echo
    echo "This will NOT remove:"
    echo "  - PostgreSQL server (if you want to keep it)"
    echo "  - Redis server (if you want to keep it)"
    echo "  - System packages (RPMs)"
    echo "  - Backups (will prompt separately)"
    echo
fi

if ! confirm "Continue with cleanup?"; then
    print_info "Cleanup cancelled"
    exit 0
fi

# Stop services
print_info "Stopping NetBox services..."
if systemctl is-active --quiet netbox; then
    systemctl stop netbox 2>/dev/null || true
    print_success "Stopped netbox service"
fi

if systemctl is-active --quiet netbox-rq; then
    systemctl stop netbox-rq 2>/dev/null || true
    print_success "Stopped netbox-rq service"
fi

# Disable services
print_info "Disabling NetBox services..."
if systemctl is-enabled --quiet netbox 2>/dev/null; then
    systemctl disable netbox 2>/dev/null || true
    print_success "Disabled netbox service"
fi

if systemctl is-enabled --quiet netbox-rq 2>/dev/null; then
    systemctl disable netbox-rq 2>/dev/null || true
    print_success "Disabled netbox-rq service"
fi

# Remove systemd service files
print_info "Removing systemd service files..."
if [[ -f /etc/systemd/system/netbox.service ]]; then
    rm -f /etc/systemd/system/netbox.service
    print_success "Removed netbox.service"
fi

if [[ -f /etc/systemd/system/netbox-rq.service ]]; then
    rm -f /etc/systemd/system/netbox-rq.service
    print_success "Removed netbox-rq.service"
fi

# Reload systemd
systemctl daemon-reload
print_success "Reloaded systemd daemon"

# Drop PostgreSQL database and user
print_info "Removing NetBox database and user..."
if systemctl is-active --quiet postgresql; then
    # Drop database
    if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw netbox; then
        sudo -u postgres psql -c "DROP DATABASE netbox;" 2>/dev/null || true
        print_success "Dropped database: netbox"
    fi

    # Drop user
    if sudo -u postgres psql -c '\du' | grep -qw netbox; then
        sudo -u postgres psql -c "DROP USER netbox;" 2>/dev/null || true
        print_success "Dropped user: netbox"
    fi
else
    print_warn "PostgreSQL not running, skipping database cleanup"
fi

# Remove NetBox system user
print_info "Removing NetBox system user..."
if id -u netbox &>/dev/null; then
    userdel -r netbox 2>/dev/null || userdel netbox 2>/dev/null || true
    print_success "Removed user: netbox"
fi

# Remove installation directory
print_info "Removing NetBox installation directory..."
if [[ -d "$INSTALL_PATH" ]]; then
    rm -rf "$INSTALL_PATH"
    print_success "Removed directory: $INSTALL_PATH"
fi

# Remove Nginx configuration
print_info "Removing Nginx configuration..."
if [[ -f /etc/nginx/conf.d/netbox.conf ]]; then
    rm -f /etc/nginx/conf.d/netbox.conf
    print_success "Removed /etc/nginx/conf.d/netbox.conf"
fi

if [[ -f /etc/nginx/sites-enabled/netbox ]]; then
    rm -f /etc/nginx/sites-enabled/netbox
    print_success "Removed /etc/nginx/sites-enabled/netbox"
fi

# Reload Nginx if running
if systemctl is-active --quiet nginx; then
    systemctl reload nginx 2>/dev/null || true
    print_success "Reloaded Nginx"
fi

# Remove firewall rules for HTTP/HTTPS
if systemctl is-active --quiet firewalld; then
    print_info "Removing firewall rules for HTTP/HTTPS..."

    if firewall-cmd --permanent --remove-service=http 2>/dev/null; then
        print_success "Removed HTTP firewall rule"
    fi

    if firewall-cmd --permanent --remove-service=https 2>/dev/null; then
        print_success "Removed HTTPS firewall rule"
    fi

    if firewall-cmd --reload 2>/dev/null; then
        print_success "Reloaded firewall configuration"
    fi
fi

# Clean up gunicorn PID file
if [[ -f /var/tmp/netbox.pid ]]; then
    rm -f /var/tmp/netbox.pid
    print_success "Removed /var/tmp/netbox.pid"
fi

# Remove offline package extracted directories
if [[ ${#PACKAGE_EXTRACT_DIRS[@]} -gt 0 ]]; then
    print_info "Removing offline package directories..."
    for dir in "${PACKAGE_EXTRACT_DIRS[@]}"; do
        if [[ -d "$dir" ]]; then
            rm -rf "$dir"
            print_success "Removed directory: $dir"
        fi
    done
else
    print_info "No offline package directories found"
fi

# Remove offline package tarballs
if [[ ${#PACKAGE_TARBALLS[@]} -gt 0 ]]; then
    print_info "Removing offline package tarballs..."
    for tarball in "${PACKAGE_TARBALLS[@]}"; do
        if [[ -f "$tarball" ]]; then
            rm -f "$tarball"
            print_success "Removed file: $tarball"
        fi
    done
else
    print_info "No offline package tarballs found"
fi

# Ask about removing backups (in force mode, always remove)
echo
if [[ -d "$BACKUP_DIR" ]]; then
    if [[ "$FORCE_MODE" == true ]]; then
        print_info "Removing backup directory: $BACKUP_DIR"
        rm -rf "$BACKUP_DIR"
        print_success "Removed backup directory"
    else
        print_info "Found backup directory: $BACKUP_DIR"
        if confirm "Remove backup directory?"; then
            rm -rf "$BACKUP_DIR"
            print_success "Removed backup directory"
        else
            print_info "Keeping backup directory"
        fi
    fi
fi

# Ask about removing log file (in force mode, always remove)
echo
if [[ -f "$LOG_FILE" ]]; then
    if [[ "$FORCE_MODE" == true ]]; then
        print_info "Removing log file: $LOG_FILE"
        rm -f "$LOG_FILE"
        print_success "Removed log file"
    else
        print_info "Found log file: $LOG_FILE"
        if confirm "Remove log file?"; then
            rm -f "$LOG_FILE"
            print_success "Removed log file"
        else
            print_info "Keeping log file"
        fi
    fi
fi

# Ask about stopping PostgreSQL and Redis (in force mode, always stop)
echo
if [[ "$FORCE_MODE" == true ]]; then
    print_info "Stopping PostgreSQL and Redis services..."
    if systemctl is-active --quiet postgresql; then
        systemctl stop postgresql
        print_success "Stopped PostgreSQL"
    fi
    if systemctl is-active --quiet redis; then
        systemctl stop redis
        print_success "Stopped Redis"
    fi
else
    print_info "Optional: Stop PostgreSQL and Redis services"
    if confirm "Stop PostgreSQL service?" "n"; then
        systemctl stop postgresql
        print_success "Stopped PostgreSQL"
    fi

    if confirm "Stop Redis service?" "n"; then
        systemctl stop redis
        print_success "Stopped Redis"
    fi
fi

# Ask about removing PostgreSQL data directory (in force mode, always remove)
echo
POSTGRESQL_DATA_DIR="/var/lib/pgsql/data"
if [[ -d "$POSTGRESQL_DATA_DIR" ]]; then
    if [[ "$FORCE_MODE" == true ]]; then
        print_info "Removing PostgreSQL data directory: $POSTGRESQL_DATA_DIR"
        rm -rf "$POSTGRESQL_DATA_DIR"
        print_success "Removed PostgreSQL data directory"
    else
        print_warn "Found PostgreSQL data directory: $POSTGRESQL_DATA_DIR"
        print_warn "This contains database clusters and should be removed for clean testing"
        if confirm "Remove PostgreSQL data directory?" "y"; then
            rm -rf "$POSTGRESQL_DATA_DIR"
            print_success "Removed PostgreSQL data directory"
        else
            print_info "Keeping PostgreSQL data directory"
            print_warn "WARNING: Old PostgreSQL data may cause version conflicts"
        fi
    fi
fi

# Summary
echo
echo "================================================================================"
print_success "Cleanup Complete"
echo "================================================================================"
echo
print_info "The test environment has been cleaned up"
print_info "You can now run a fresh installation"
echo

# Show cleanup summary
echo "Removed:"
echo "  - NetBox application and services"
echo "  - NetBox database and PostgreSQL user"
echo "  - Systemd service files"
echo "  - Nginx configuration for NetBox"
echo "  - Firewall rules for HTTP/HTTPS"
echo "  - NetBox system user"
echo "  - Offline installer package files"

if [[ "$FORCE_MODE" == true ]]; then
    echo "  - PostgreSQL data directory"
    echo "  - Backup directory"
    echo "  - Installation log file"
fi
echo

# Show what remains
echo "Still present (not removed by this script):"
echo "  - PostgreSQL server package (status: $(systemctl is-active postgresql 2>/dev/null || echo 'stopped'))"
echo "  - Redis server package (status: $(systemctl is-active redis 2>/dev/null || echo 'stopped'))"
echo "  - Nginx server package (status: $(systemctl is-active nginx 2>/dev/null || echo 'running'))"
echo "  - Other system packages (Python, development tools, etc.)"
echo ""
echo "To list installed packages: rpm -qa | grep -E 'postgresql|redis|nginx|python'"
echo

exit 0
