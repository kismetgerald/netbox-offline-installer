#!/bin/bash
#
# NetBox Offline Installer - Rollback Module
# Version: 0.0.1
# Description: Backup creation, management, and restoration
#
# Created by: Kismet Agbasi (KismetG17@gmail.com)
# AI Collaborator: Claude Code (integrated with VS Code)
# Date Created: 12/27/2025
# Last Updated: 01/11/2026
#
# This module provides comprehensive backup and rollback functionality:
# - Create full installation backups (configuration, database, media, installation directory)
# - List and manage available backups
# - Restore from backups with verification
# - Enforce backup retention policies
#

# =============================================================================
# BACKUP CONFIGURATION
# =============================================================================

# Default backup directory
DEFAULT_BACKUP_DIR="/var/backup/netbox-offline-installer"

# Default backup retention count
DEFAULT_BACKUP_RETENTION=3

# Backup directory naming pattern
BACKUP_DIR_PATTERN="backup-*"

# =============================================================================
# BACKUP CREATION
# =============================================================================

# Generate backup directory name with timestamp
generate_backup_dirname() {
    local backup_type="${1:-manual}"
    local timestamp
    timestamp=$(date '+%Y%m%d-%H%M%S')

    echo "backup-${timestamp}-${backup_type}"
}

# Create backup directory structure
create_backup_directory() {
    local backup_dir="$1"

    log_function_entry

    log_info "Creating backup directory: $backup_dir"

    # Create main backup directory
    if ! mkdir -p "$backup_dir"; then
        log_error "Failed to create backup directory: $backup_dir"
        log_function_exit 1
        return 1
    fi

    # Fix #46 (final): Ensure ALL parent directories allow traversal by netbox user
    # Both /var/backup and /var/backup/netbox-offline-installer may have restrictive
    # permissions (700) that prevent the netbox user from accessing subdirectories
    # We need to fix permissions on the entire parent chain
    local parent_dir
    parent_dir=$(dirname "$backup_dir")

    # Fix /var/backup permissions first (may be 700 by default)
    if [[ -d "/var/backup" ]]; then
        chmod 755 "/var/backup" 2>/dev/null || \
            log_warn "Could not set permissions on /var/backup"
    fi

    # Fix /var/backup/netbox-offline-installer permissions
    if [[ -d "$parent_dir" ]]; then
        chmod 755 "$parent_dir" 2>/dev/null || \
            log_warn "Could not set permissions on parent backup directory: $parent_dir"
    fi

    # Create subdirectories
    local subdirs=("config" "database" "media")

    for subdir in "${subdirs[@]}"; do
        if ! mkdir -p "$backup_dir/$subdir"; then
            log_error "Failed to create subdirectory: $subdir"
            log_function_exit 1
            return 1
        fi
    done

    # Fix #46 (revised): Set secure permissions on entire backup directory tree
    # Subdirectories created by mkdir inherit umask (mode 700), so we need to
    # explicitly set 750 on all directories to allow group read/execute access
    chmod -R 750 "$backup_dir"

    log_function_exit 0
    return 0
}

# Backup NetBox configuration files
backup_configuration() {
    local install_path="$1"
    local backup_dir="$2"

    log_function_entry

    log_info "Backing up NetBox configuration..."

    local config_file="${install_path}/netbox/netbox/configuration.py"
    local backup_config_dir="${backup_dir}/config"

    if [[ ! -f "$config_file" ]]; then
        log_warn "Configuration file not found: $config_file"
        log_function_exit 1
        return 1
    fi

    # Copy configuration file
    if cp "$config_file" "$backup_config_dir/configuration.py"; then
        log_info "Configuration backed up"
    else
        log_error "Failed to backup configuration"
        log_function_exit 1
        return 1
    fi

    # Backup other configuration files if they exist
    local other_configs=(
        "${install_path}/netbox/netbox/ldap_config.py"
        "${install_path}/gunicorn.py"
    )

    for config in "${other_configs[@]}"; do
        if [[ -f "$config" ]]; then
            cp "$config" "$backup_config_dir/" 2>/dev/null && \
                log_debug "Backed up: $(basename "$config")"
        fi
    done

    log_function_exit 0
    return 0
}

# Backup PostgreSQL database
backup_database() {
    local db_host="$1"
    local db_port="$2"
    local db_name="$3"
    local db_user="$4"
    local db_password="$5"
    local backup_dir="$6"

    log_function_entry

    log_info "Backing up PostgreSQL database: $db_name"

    local backup_db_dir="${backup_dir}/database"
    local dump_file="${backup_db_dir}/database.sql"

    # Fix #44: Set ownership of backup directory to netbox user
    # The backup directory is created by root, but pg_dump runs as netbox user
    # and needs write permissions to create the database dump file
    chown -R netbox:netbox "$backup_dir" >> "$LOG_FILE" 2>&1

    # Fix #46 (revised): Set SELinux context to allow netbox user to write backup files
    # The backup directory is created with var_t context which prevents confined users from writing
    # Change to tmp_t (same as /tmp) to allow file operations by confined users via sudo
    # This must be done AFTER ownership change to ensure proper context propagation
    if command -v chcon &>/dev/null && getenforce 2>/dev/null | grep -qi "enforcing\|permissive"; then
        chcon -R -t tmp_t "$backup_dir" >> "$LOG_FILE" 2>&1 || \
            log_warn "Failed to set SELinux context on backup directory"
    fi

    # Set PGPASSWORD for pg_dump
    export PGPASSWORD="$db_password"

    # Perform database dump
    # IMPORTANT: Use 127.0.0.1 instead of localhost to force IPv4 (md5 auth)
    # Run as netbox user to satisfy authentication requirements
    log_info "Running pg_dump..."

    # Force IPv4 by using 127.0.0.1 (matches pg_hba.conf md5 auth rule)
    # Use -h 127.0.0.1 instead of localhost to avoid IPv6 ident auth
    local db_host_ipv4
    if [[ "$db_host" == "localhost" ]]; then
        db_host_ipv4="127.0.0.1"
    else
        db_host_ipv4="$db_host"
    fi

    # Fix #46 (revised): Change working directory to /tmp before running pg_dump
    # The sudo command inherits the CWD, which may be /root (inaccessible to netbox user)
    # This causes "could not change directory" error even though backup path is accessible
    if sudo -u netbox bash -c "cd /tmp && PGPASSWORD='$db_password' pg_dump -h '$db_host_ipv4' -p '$db_port' -U '$db_user' -d '$db_name' -F p -f '$dump_file'" >> "$LOG_FILE" 2>&1; then

        # Get dump file size
        local dump_size
        dump_size=$(du -sh "$dump_file" | awk '{print $1}')

        log_info "Database dump completed: $dump_file"
        log_info "Database dump size: $dump_size"

        # Compress dump file
        log_info "Compressing database dump..."

        if gzip "$dump_file"; then
            local compressed_size
            compressed_size=$(du -sh "${dump_file}.gz" | awk '{print $1}')
            log_info "Compressed to: $compressed_size"
        else
            log_warn "Failed to compress database dump (non-critical)"
        fi

        unset PGPASSWORD
        log_function_exit 0
        return 0
    else
        log_error "Database dump failed"
        unset PGPASSWORD
        log_function_exit 1
        return 1
    fi
}

# Backup NetBox media files
backup_media() {
    local install_path="$1"
    local backup_dir="$2"

    log_function_entry

    local media_source="${install_path}/netbox/media"
    local backup_media_dir="${backup_dir}/media"

    if [[ ! -d "$media_source" ]]; then
        log_warn "Media directory not found: $media_source"
        log_function_exit 0
        return 0
    fi

    # Check if media directory has content
    if [[ -z "$(ls -A "$media_source" 2>/dev/null)" ]]; then
        log_info "Media directory is empty, skipping"
        log_function_exit 0
        return 0
    fi

    log_info "Backing up media files..."

    # Copy media directory
    if cp -r "$media_source"/* "$backup_media_dir/" 2>&1 | tee -a "$LOG_FILE"; then
        local media_size
        media_size=$(du -sh "$backup_media_dir" | awk '{print $1}')
        log_info "Media files backed up: $media_size"
        log_function_exit 0
        return 0
    else
        log_warn "Failed to backup media files (non-critical)"
        log_function_exit 1
        return 1
    fi
}

# Create installation directory tarball
backup_installation() {
    local install_path="$1"
    local backup_dir="$2"

    log_function_entry

    log_info "Creating installation directory tarball..."

    local tarball="${backup_dir}/installation.tar.gz"

    # Create tarball of installation directory
    # Exclude venv to save space (can be recreated)
    if tar -czf "$tarball" \
        --exclude="$install_path/venv" \
        --exclude="$install_path/netbox/static" \
        -C "$(dirname "$install_path")" \
        "$(basename "$install_path")" \
        2>&1 | tee -a "$LOG_FILE"; then

        local tarball_size
        tarball_size=$(du -sh "$tarball" | awk '{print $1}')

        log_info "Installation tarball created: $tarball"
        log_info "Tarball size: $tarball_size"

        log_function_exit 0
        return 0
    else
        log_error "Failed to create installation tarball"
        log_function_exit 1
        return 1
    fi
}

# Generate backup metadata
generate_backup_metadata() {
    local backup_dir="$1"
    local install_path="$2"
    local backup_type="$3"

    log_function_entry

    local metadata_file="${backup_dir}/metadata.txt"

    # Detect current NetBox version from release.yaml
    local netbox_version="unknown"
    local version_file="${install_path}/netbox/release.yaml"
    if [[ -f "$version_file" ]]; then
        netbox_version=$(grep -oP '^version:\s*["\047]?\K[0-9]+\.[0-9]+\.[0-9]+' \
            "$version_file" 2>/dev/null || echo "unknown")
    fi

    # Calculate backup size
    local backup_size
    backup_size=$(du -sh "$backup_dir" | awk '{print $1}')

    # Generate checksums for critical files
    local db_checksum config_checksum tarball_checksum

    if [[ -f "$backup_dir/database/database.sql.gz" ]]; then
        db_checksum=$(sha256sum "$backup_dir/database/database.sql.gz" | awk '{print $1}')
    else
        db_checksum="N/A"
    fi

    if [[ -f "$backup_dir/config/configuration.py" ]]; then
        config_checksum=$(sha256sum "$backup_dir/config/configuration.py" | awk '{print $1}')
    else
        config_checksum="N/A"
    fi

    if [[ -f "$backup_dir/installation.tar.gz" ]]; then
        tarball_checksum=$(sha256sum "$backup_dir/installation.tar.gz" | awk '{print $1}')
    else
        tarball_checksum="N/A"
    fi

    # Write metadata
    cat > "$metadata_file" <<EOF
===============================================================================
NetBox Backup Metadata
===============================================================================
Backup Type:        $backup_type
Backup Date:        $(date '+%Y-%m-%d %H:%M:%S %Z')
Hostname:           $(hostname)
NetBox Version:     v${netbox_version}
Install Path:       ${install_path}
Backup Size:        ${backup_size}

===============================================================================
Backup Contents
===============================================================================
Configuration:      $(ls -1 "$backup_dir/config" 2>/dev/null | wc -l) files
Database:           $(ls -1 "$backup_dir/database" 2>/dev/null | wc -l) files
Media Files:        $(find "$backup_dir/media" -type f 2>/dev/null | wc -l) files
Installation:       installation.tar.gz

===============================================================================
Checksums (SHA256)
===============================================================================
Database:           $db_checksum
Configuration:      $config_checksum
Installation:       $tarball_checksum

===============================================================================
System Information
===============================================================================
RHEL Version:       $(get_rhel_version)
PostgreSQL:         $(psql --version 2>/dev/null | head -1 || echo "Not available")
Python:             $(python3 --version 2>/dev/null || echo "Not available")
Kernel:             $(uname -r)

===============================================================================
Notes
===============================================================================
This backup can be restored using the NetBox Offline Installer rollback
functionality. Ensure the target system matches the RHEL version and has
compatible PostgreSQL installed.

Restore command:
  ./netbox-installer.sh rollback -b $(basename "$backup_dir")

===============================================================================
EOF

    log_info "Metadata generated: $metadata_file"
    log_function_exit 0
    return 0
}

# Create complete NetBox backup
create_netbox_backup() {
    local install_path="${1:-${INSTALL_PATH:-/opt/netbox}}"
    local backup_type="${2:-manual}"

    log_function_entry
    log_section "Creating NetBox Backup"

    # Validate installation exists
    if [[ ! -d "$install_path" ]]; then
        log_error "NetBox installation not found: $install_path"
        log_function_exit 1
        return 1
    fi

    # Get database credentials from configuration
    local db_host db_port db_name db_user db_password
    local config_file="$install_path/netbox/netbox/configuration.py"

    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found"
        log_function_exit 1
        return 1
    fi

    # Fix #35 & #49: Auto-extract database password from configuration.py
    # Extract fields ONLY from DATABASES block to avoid conflicts with REDIS/SMTP ports
    # Strategy: Extract DATABASES block first, then parse fields from that block only
    # The DATABASES dictionary format is:
    #     DATABASES = {
    #         'default': {
    #             'NAME': 'value',
    #             'USER': 'value',
    #             'PASSWORD': 'value',
    #             'HOST': 'value',
    #             'PORT': value,
    #         }
    #     }

    # Extract entire DATABASES block (from "DATABASES = {" to closing "}")
    local databases_block
    databases_block=$(sed -n '/^DATABASES = {/,/^}/p' "$config_file")

    # Now extract fields from DATABASES block only
    db_name=$(echo "$databases_block" | grep -E "^\s*'NAME'\s*:" | sed -E "s/^\s*'NAME'\s*:\s*['\"]([^'\"]+)['\"].*/\1/")
    db_user=$(echo "$databases_block" | grep -E "^\s*'USER'\s*:" | sed -E "s/^\s*'USER'\s*:\s*['\"]([^'\"]+)['\"].*/\1/")
    db_password=$(echo "$databases_block" | grep -E "^\s*'PASSWORD'\s*:" | sed -E "s/^\s*'PASSWORD'\s*:\s*['\"]([^'\"]+)['\"].*/\1/")
    db_host=$(echo "$databases_block" | grep -E "^\s*'HOST'\s*:" | sed -E "s/^\s*'HOST'\s*:\s*['\"]([^'\"]+)['\"].*/\1/")
    db_port=$(echo "$databases_block" | grep -E "^\s*'PORT'\s*:" | sed -E "s/^\s*'PORT'\s*:\s*([0-9]+).*/\1/")

    # Set defaults if not found
    db_host="${db_host:-localhost}"
    db_port="${db_port:-5432}"
    db_name="${db_name:-netbox}"
    db_user="${db_user:-netbox}"

    # Fix #35: Only prompt for password if extraction failed
    if [[ -z "$db_password" ]]; then
        log_warn "Could not extract database password from configuration"
        db_password=$(prompt_password "Enter database password for backup")
    else
        log_debug "Database credentials extracted from configuration"
    fi

    # Generate backup directory name
    local backup_base_dir="${BACKUP_DIR:-$DEFAULT_BACKUP_DIR}"
    local backup_dirname
    backup_dirname=$(generate_backup_dirname "$backup_type")
    local backup_dir="${backup_base_dir}/${backup_dirname}"

    log_info "Backup directory: $backup_dir"

    # Create backup directory structure
    create_backup_directory "$backup_dir" || {
        log_error "Failed to create backup directory"
        log_function_exit 1
        return 1
    }

    # Backup configuration
    log_subsection "Configuration Backup"
    backup_configuration "$install_path" "$backup_dir" || {
        log_error "Configuration backup failed"
        log_function_exit 1
        return 1
    }

    # Backup database
    log_subsection "Database Backup"
    backup_database "$db_host" "$db_port" "$db_name" "$db_user" "$db_password" "$backup_dir" || {
        log_error "Database backup failed"
        log_function_exit 1
        return 1
    }

    # Backup media files
    log_subsection "Media Files Backup"
    backup_media "$install_path" "$backup_dir"

    # Backup installation directory
    log_subsection "Installation Directory Backup"
    backup_installation "$install_path" "$backup_dir" || {
        log_error "Installation backup failed"
        log_function_exit 1
        return 1
    }

    # Generate metadata
    generate_backup_metadata "$backup_dir" "$install_path" "$backup_type"

    # Calculate total backup size
    local total_size
    total_size=$(du -sh "$backup_dir" | awk '{print $1}')

    log_success_summary "Backup Creation"
    log_info "Backup location: $backup_dir"
    log_info "Backup size: $total_size"
    log_security "NetBox backup created: $(basename "$backup_dir")"

    # Enforce retention policy (protect source backup during rollback if specified)
    cleanup_old_backups "${PROTECTED_BACKUP:-}"

    echo "$backup_dir"
    log_function_exit 0
    return 0
}

# =============================================================================
# BACKUP MANAGEMENT
# =============================================================================

# List all available backups
list_backups() {
    local backup_base_dir="${BACKUP_DIR:-$DEFAULT_BACKUP_DIR}"

    log_function_entry

    if [[ ! -d "$backup_base_dir" ]]; then
        log_info "No backups found (backup directory doesn't exist)"
        log_function_exit 0
        return 0
    fi

    log_section "Available Backups"

    # Find all backup directories
    local backups
    backups=$(find "$backup_base_dir" -maxdepth 1 -type d -name "$BACKUP_DIR_PATTERN" 2>/dev/null | sort -r)

    if [[ -z "$backups" ]]; then
        log_info "No backups found in $backup_base_dir"
        log_function_exit 0
        return 0
    fi

    local backup_count=0

    echo
    echo "Backups in $backup_base_dir:"
    echo "================================================================================"

    while IFS= read -r backup_dir; do
        ((backup_count++))

        local backup_name
        backup_name=$(basename "$backup_dir")

        local backup_date backup_size netbox_version

        # Read metadata if available
        if [[ -f "$backup_dir/metadata.txt" ]]; then
            # Try new format first (with "Backup Date:" field)
            backup_date=$(grep "Backup Date:" "$backup_dir/metadata.txt" | cut -d: -f2- | xargs)

            # Fall back to old format (with "Timestamp:" field)
            if [[ -z "$backup_date" ]]; then
                backup_date=$(grep "Timestamp:" "$backup_dir/metadata.txt" | cut -d: -f2- | xargs)
            fi

            # Try to get backup size
            backup_size=$(grep "Backup Size:" "$backup_dir/metadata.txt" | awk '{print $3}')

            # If not found, calculate it
            if [[ -z "$backup_size" ]]; then
                backup_size=$(du -sh "$backup_dir" 2>/dev/null | awk '{print $1}')
            fi

            # Get NetBox version (handles both "v4.4.8" and "4.4.8" formats)
            netbox_version=$(grep "NetBox Version:" "$backup_dir/metadata.txt" | awk '{print $3}')

            # Add "v" prefix if missing and version is valid
            if [[ -n "$netbox_version" && "$netbox_version" != "unknown" && "$netbox_version" != "vunknown" ]]; then
                if [[ ! "$netbox_version" =~ ^v ]]; then
                    netbox_version="v${netbox_version}"
                fi
            fi
        else
            # No metadata file - use filesystem stats
            backup_date=$(stat -c '%y' "$backup_dir" 2>/dev/null | cut -d' ' -f1 || \
                          stat -f '%Sm' -t '%Y-%m-%d' "$backup_dir" 2>/dev/null)
            backup_size=$(du -sh "$backup_dir" 2>/dev/null | awk '{print $1}')
            netbox_version="unknown"
        fi

        echo "${backup_count}. $backup_name"
        echo "   Date:    $backup_date"
        echo "   Size:    $backup_size"
        echo "   Version: $netbox_version"
        echo

    done <<< "$backups"

    echo "================================================================================"
    echo "Total backups: $backup_count"
    echo

    log_function_exit 0
    return 0
}

# Get backup details
get_backup_details() {
    local backup_name="$1"
    local backup_base_dir="${BACKUP_DIR:-$DEFAULT_BACKUP_DIR}"
    local backup_dir="${backup_base_dir}/${backup_name}"

    if [[ ! -d "$backup_dir" ]]; then
        log_error "Backup not found: $backup_name"
        return 1
    fi

    if [[ -f "$backup_dir/metadata.txt" ]]; then
        cat "$backup_dir/metadata.txt"
    else
        echo "No metadata available for backup: $backup_name"
    fi

    return 0
}

# Cleanup old backups based on retention policy
cleanup_old_backups() {
    local backup_base_dir="${BACKUP_DIR:-$DEFAULT_BACKUP_DIR}"
    local retention="${BACKUP_RETENTION:-$DEFAULT_BACKUP_RETENTION}"
    local protect_backup="${1:-}"  # Optional: backup name to protect from deletion

    log_function_entry

    if [[ ! -d "$backup_base_dir" ]]; then
        log_debug "Backup directory doesn't exist, nothing to clean"
        log_function_exit 0
        return 0
    fi

    # Skip cleanup if retention is 0 (unlimited)
    if [[ $retention -eq 0 ]]; then
        log_debug "Backup retention is unlimited, skipping cleanup"
        log_function_exit 0
        return 0
    fi

    log_info "Enforcing backup retention policy (keep last $retention backups)"

    if [[ -n "$protect_backup" ]]; then
        log_debug "Protecting backup from deletion: $protect_backup"
    fi

    # Find all backup directories sorted by date (newest first)
    local all_backups
    all_backups=$(find "$backup_base_dir" -maxdepth 1 -type d -name "$BACKUP_DIR_PATTERN" 2>/dev/null | sort -r)

    local backup_count
    backup_count=$(echo "$all_backups" | grep -c "^" || echo 0)

    if [[ $backup_count -le $retention ]]; then
        log_info "Backup count ($backup_count) within retention limit ($retention)"
        log_function_exit 0
        return 0
    fi

    # Delete old backups
    local to_delete=$((backup_count - retention))

    log_info "Deleting $to_delete old backup(s)..."

    echo "$all_backups" | tail -n "$to_delete" | while IFS= read -r backup_dir; do
        local backup_name
        backup_name=$(basename "$backup_dir")

        # Skip protected backup
        if [[ -n "$protect_backup" && "$backup_name" == "$protect_backup" ]]; then
            log_debug "Skipping protected backup: $backup_name"
            continue
        fi

        log_info "Removing old backup: $backup_name"

        if rm -rf "$backup_dir"; then
            log_audit "Backup deleted: $backup_name (retention policy)"
        else
            log_warn "Failed to delete backup: $backup_name"
        fi
    done

    log_function_exit 0
    return 0
}

# =============================================================================
# BACKUP RESTORATION
# =============================================================================

# Restore NetBox configuration from backup
restore_configuration() {
    local backup_dir="$1"
    local install_path="$2"

    log_function_entry
    log_subsection "Restoring Configuration"

    local backup_config="${backup_dir}/config/configuration.py"
    local target_config="${install_path}/netbox/netbox/configuration.py"

    if [[ ! -f "$backup_config" ]]; then
        log_error "Configuration backup not found: $backup_config"
        log_function_exit 1
        return 1
    fi

    log_info "Restoring configuration..."

    # Backup current configuration (safety)
    if [[ -f "$target_config" ]]; then
        cp "$target_config" "${target_config}.pre-restore" 2>/dev/null
    fi

    # Restore configuration
    if cp "$backup_config" "$target_config"; then
        chmod 640 "$target_config"
        log_info "Configuration restored"
        log_function_exit 0
        return 0
    else
        log_error "Failed to restore configuration"
        log_function_exit 1
        return 1
    fi
}

# Restore PostgreSQL database from backup
restore_database() {
    local backup_dir="$1"
    local db_host="$2"
    local db_port="$3"
    local db_name="$4"
    local db_user="$5"
    local db_password="$6"

    log_function_entry
    log_subsection "Restoring Database"

    # Find database dump file
    local dump_file
    if [[ -f "$backup_dir/database/database.sql.gz" ]]; then
        dump_file="$backup_dir/database/database.sql.gz"
    elif [[ -f "$backup_dir/database/database.sql" ]]; then
        dump_file="$backup_dir/database/database.sql"
    else
        log_error "Database dump not found in backup"
        log_function_exit 1
        return 1
    fi

    log_info "Restoring database from: $(basename "$dump_file")"
    log_warn "This will DROP and recreate the database!"

    export PGPASSWORD="$db_password"

    # Drop existing database
    log_info "Dropping existing database..."

    # Fix #47: Add working directory change to avoid permission errors
    if sudo -u postgres bash -c "cd /tmp && psql -c 'DROP DATABASE IF EXISTS ${db_name};'" >> "$LOG_FILE" 2>&1; then
        log_info "Existing database dropped"
    else
        log_error "Failed to drop database"
        unset PGPASSWORD
        log_function_exit 1
        return 1
    fi

    # Recreate database
    log_info "Creating fresh database..."

    # Fix #47: Add working directory change to avoid permission errors
    if sudo -u postgres bash -c "cd /tmp && psql -c 'CREATE DATABASE ${db_name} OWNER ${db_user};'" >> "$LOG_FILE" 2>&1; then
        log_info "Database created"
    else
        log_error "Failed to create database"
        unset PGPASSWORD
        log_function_exit 1
        return 1
    fi

    # Restore from dump
    log_info "Restoring database content (this may take several minutes)..."

    # Force IPv4 by using 127.0.0.1 (matches pg_hba.conf md5 auth rule)
    local db_host_ipv4
    if [[ "$db_host" == "localhost" ]]; then
        db_host_ipv4="127.0.0.1"
    else
        db_host_ipv4="$db_host"
    fi

    # Fix #47 refinement (final): Create .pgpass in netbox home directory
    # PostgreSQL automatically reads ~/.pgpass when authenticating
    # This bypasses all sudo environment variable issues
    local netbox_home
    netbox_home=$(getent passwd netbox | cut -d: -f6)
    local pgpass_file="${netbox_home}/.pgpass"

    # Create .pgpass file in netbox's home directory
    echo "$db_host_ipv4:$db_port:$db_name:$db_user:$db_password" > "$pgpass_file"
    chmod 600 "$pgpass_file"
    chown netbox:netbox "$pgpass_file"

    if [[ "$dump_file" == *.gz ]]; then
        # Decompress and restore
        # PostgreSQL will automatically read ~/.pgpass for authentication
        if sudo -u netbox bash -c "cd /tmp && gunzip -c '$dump_file' | psql -h '$db_host_ipv4' -p '$db_port' -U '$db_user' -d '$db_name'" >> "$LOG_FILE" 2>&1; then
            log_info "Database restored successfully"
        else
            log_error "Database restoration failed"
            rm -f "$pgpass_file"
            log_function_exit 1
            return 1
        fi
    else
        # Restore directly
        # PostgreSQL will automatically read ~/.pgpass for authentication
        if sudo -u netbox bash -c "cd /tmp && psql -h '$db_host_ipv4' -p '$db_port' -U '$db_user' -d '$db_name' -f '$dump_file'" >> "$LOG_FILE" 2>&1; then
            log_info "Database restored successfully"
        else
            log_error "Database restoration failed"
            rm -f "$pgpass_file"
            log_function_exit 1
            return 1
        fi
    fi

    # Clean up .pgpass file
    rm -f "$pgpass_file"
    log_function_exit 0
    return 0
}

# Restore NetBox media files from backup
restore_media() {
    local backup_dir="$1"
    local install_path="$2"

    log_function_entry
    log_subsection "Restoring Media Files"

    local backup_media="${backup_dir}/media"
    local target_media="${install_path}/netbox/media"

    if [[ ! -d "$backup_media" ]]; then
        log_warn "Media backup not found (may be empty)"
        log_function_exit 0
        return 0
    fi

    # Check if media backup has content
    if [[ -z "$(ls -A "$backup_media" 2>/dev/null)" ]]; then
        log_info "Media backup is empty, skipping"
        log_function_exit 0
        return 0
    fi

    log_info "Restoring media files..."

    # Create media directory if doesn't exist
    mkdir -p "$target_media"

    # Restore media files
    if cp -r "$backup_media"/* "$target_media/" 2>&1 | tee -a "$LOG_FILE"; then
        log_info "Media files restored"
        log_function_exit 0
        return 0
    else
        log_warn "Failed to restore media files (non-critical)"
        log_function_exit 1
        return 1
    fi
}

# Restore installation directory from backup
restore_installation() {
    local backup_dir="$1"
    local install_path="$2"

    log_function_entry
    log_subsection "Restoring Installation Directory"

    local tarball="${backup_dir}/installation.tar.gz"

    if [[ ! -f "$tarball" ]]; then
        log_error "Installation tarball not found: $tarball"
        log_function_exit 1
        return 1
    fi

    log_info "Restoring installation directory from tarball..."
    log_warn "This will replace the current installation!"

    # Stop services first
    log_info "Stopping NetBox services..."
    systemctl stop netbox netbox-rq &>/dev/null

    # Extract tarball
    if tar -xzf "$tarball" -C "$(dirname "$install_path")" 2>&1 | tee -a "$LOG_FILE"; then
        log_info "Installation directory restored"
        log_function_exit 0
        return 0
    else
        log_error "Failed to restore installation directory"
        log_function_exit 1
        return 1
    fi
}

# Perform complete NetBox restoration from backup
restore_from_backup() {
    local backup_name="$1"
    local install_path="${2:-${INSTALL_PATH:-/opt/netbox}}"

    log_function_entry
    log_section "NetBox Restoration from Backup"

    local backup_base_dir="${BACKUP_DIR:-$DEFAULT_BACKUP_DIR}"
    local backup_dir="${backup_base_dir}/${backup_name}"

    # Validate backup exists
    if [[ ! -d "$backup_dir" ]]; then
        log_error "Backup not found: $backup_name"
        log_error "Available backups:"
        list_backups
        log_function_exit 1
        return 1
    fi

    # Display backup details
    log_info "Backup details:"
    get_backup_details "$backup_name" | head -20
    echo

    # Confirm restoration
    log_warn "This will restore NetBox from backup: $backup_name"
    log_warn "Current installation will be replaced!"
    echo

    if ! confirm_action "Continue with restoration?" "n"; then
        log_info "Restoration cancelled by user"
        log_function_exit 0
        return 0
    fi

    # Create pre-rollback backup (safety net)
    # IMPORTANT: Protect source backup from retention policy deletion
    log_info "Creating pre-rollback safety backup..."
    local safety_backup

    # Temporarily protect source backup from deletion during safety backup creation
    export PROTECTED_BACKUP="$backup_name"
    safety_backup=$(create_netbox_backup "$install_path" "pre-rollback")
    unset PROTECTED_BACKUP

    log_info "Safety backup created: $(basename "$safety_backup")"

    # Stop NetBox services
    log_subsection "Stopping Services"
    systemctl stop netbox netbox-rq nginx &>/dev/null

    # Get database credentials
    local db_host db_port db_name db_user db_password
    local config_file="$backup_dir/config/configuration.py"

    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found in backup"
        log_function_exit 1
        return 1
    fi

    # Fix #35 & #49: Auto-extract database password from configuration.py
    # Extract fields ONLY from DATABASES block to avoid conflicts with REDIS/SMTP ports

    # Extract entire DATABASES block (from "DATABASES = {" to closing "}")
    local databases_block
    databases_block=$(sed -n '/^DATABASES = {/,/^}/p' "$config_file")

    # Now extract fields from DATABASES block only
    db_name=$(echo "$databases_block" | grep -E "^\s*'NAME'\s*:" | sed -E "s/^\s*'NAME'\s*:\s*['\"]([^'\"]+)['\"].*/\1/")
    db_user=$(echo "$databases_block" | grep -E "^\s*'USER'\s*:" | sed -E "s/^\s*'USER'\s*:\s*['\"]([^'\"]+)['\"].*/\1/")
    db_password=$(echo "$databases_block" | grep -E "^\s*'PASSWORD'\s*:" | sed -E "s/^\s*'PASSWORD'\s*:\s*['\"]([^'\"]+)['\"].*/\1/")
    db_host=$(echo "$databases_block" | grep -E "^\s*'HOST'\s*:" | sed -E "s/^\s*'HOST'\s*:\s*['\"]([^'\"]+)['\"].*/\1/")
    db_port=$(echo "$databases_block" | grep -E "^\s*'PORT'\s*:" | sed -E "s/^\s*'PORT'\s*:\s*([0-9]+).*/\1/")

    # Set defaults if not found
    db_host="${db_host:-localhost}"
    db_port="${db_port:-5432}"
    db_name="${db_name:-netbox}"
    db_user="${db_user:-netbox}"

    # Fix #35: Only prompt for password if extraction failed
    if [[ -z "$db_password" ]]; then
        log_warn "Could not extract database password from backup configuration"
        db_password=$(prompt_password "Enter database password for restoration")
    else
        log_debug "Database credentials extracted from backup configuration"
    fi

    # Restore database
    restore_database "$backup_dir" "$db_host" "$db_port" "$db_name" "$db_user" "$db_password" || {
        log_error "Database restoration failed"
        log_function_exit 1
        return 1
    }

    # Restore installation directory
    restore_installation "$backup_dir" "$install_path" || {
        log_error "Installation restoration failed"
        log_function_exit 1
        return 1
    }

    # Restore configuration
    restore_configuration "$backup_dir" "$install_path" || {
        log_error "Configuration restoration failed"
        log_function_exit 1
        return 1
    }

    # Restore media files
    restore_media "$backup_dir" "$install_path"

    # Set permissions
    log_subsection "Setting Permissions"
    set_secure_permissions "$install_path" "netbox" "netbox" "Rollback Restoration"

    # Restart services
    log_subsection "Starting Services"
    systemctl start netbox netbox-rq nginx 2>&1 | tee -a "$LOG_FILE"

    # Verify services
    sleep 3

    local all_running=true
    for service in netbox netbox-rq nginx; do
        if systemctl is-active --quiet "$service"; then
            log_info "✓ $service is running"
        else
            log_error "✗ $service failed to start"
            all_running=false
        fi
    done

    if [[ "$all_running" == "true" ]]; then
        log_success_summary "NetBox Restoration"
        log_info "NetBox has been restored from backup: $backup_name"
        log_security "NetBox restored from backup: $backup_name"
        log_function_exit 0
        return 0
    else
        log_error "Some services failed to start after restoration"
        log_error "Check service logs for details"
        log_function_exit 1
        return 1
    fi
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize rollback module
init_rollback() {
    log_debug "Rollback module initialized"

    # Set default backup directory if not configured
    if [[ -z "${BACKUP_DIR:-}" ]]; then
        export BACKUP_DIR="$DEFAULT_BACKUP_DIR"
    fi

    # Set default retention if not configured
    if [[ -z "${BACKUP_RETENTION:-}" ]]; then
        export BACKUP_RETENTION="$DEFAULT_BACKUP_RETENTION"
    fi
}

# Auto-initialize when sourced
init_rollback

# End of rollback.sh
