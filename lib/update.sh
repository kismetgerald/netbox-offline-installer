#!/bin/bash
#
# NetBox Offline Installer - Update Module
# Version: 0.0.1
# Description: NetBox version updates with rollback support
#
# Created by: Kismet Agbasi (KismetG17@gmail.com)
# AI Collaborator: Claude Code (integrated with VS Code)
# Date Created: 12/27/2025
# Last Updated: 01/11/2026
#
# This module handles NetBox updates from offline packages:
# - Detect current installation version
# - Validate update package compatibility
# - Create pre-update backup
# - Update Python dependencies
# - Run database migrations
# - Update static files
# - Restart services with verification
#

# =============================================================================
# VERSION DETECTION
# =============================================================================

# Detect currently installed NetBox version
get_installed_netbox_version() {
    local install_path="${1:-${INSTALL_PATH:-/opt/netbox}}"

    log_function_entry

    local version_file="${install_path}/netbox/release.yaml"

    if [[ ! -f "$version_file" ]]; then
        log_error "NetBox installation not found: $install_path"
        log_function_exit 1
        return 1
    fi

    # Extract version from release.yaml (version: "X.Y.Z")
    local version
    version=$(grep -oP '^version:\s*["\047]?\K[0-9]+\.[0-9]+\.[0-9]+' \
        "$version_file" 2>/dev/null)

    if [[ -z "$version" ]]; then
        log_error "Could not determine installed NetBox version"
        log_function_exit 1
        return 1
    fi

    echo "$version"
    log_function_exit 0
    return 0
}

# Compare NetBox versions
compare_netbox_versions() {
    local current_version="$1"
    local new_version="$2"

    log_function_entry

    log_info "Current version: v${current_version}"
    log_info "New version:     v${new_version}"

    if version_compare "$current_version" "==" "$new_version"; then
        echo "same"
        log_function_exit 0
        return 0
    elif version_compare "$current_version" "<" "$new_version"; then
        echo "upgrade"
        log_function_exit 0
        return 0
    else
        echo "downgrade"
        log_function_exit 0
        return 0
    fi
}

# =============================================================================
# UPDATE VALIDATION
# =============================================================================

# Validate update package
validate_update_package() {
    local package_dir="$1"
    local install_path="$2"

    log_function_entry
    log_subsection "Validating Update Package"

    # Validate package structure
    if ! validate_package_structure "$package_dir"; then
        log_error "Invalid update package"
        log_function_exit 1
        return 1
    fi

    # Get versions
    local current_version new_version
    current_version=$(get_installed_netbox_version "$install_path")
    new_version=$(get_package_netbox_version "$package_dir")

    if [[ -z "$current_version" || -z "$new_version" ]]; then
        log_error "Could not determine versions"
        log_function_exit 1
        return 1
    fi

    # Compare versions
    local version_relationship
    version_relationship=$(compare_netbox_versions "$current_version" "$new_version")

    case "$version_relationship" in
        same)
            log_warn "Same version already installed (v${current_version})"
            if ! confirm_action "Reinstall same version?" "n"; then
                log_info "Update cancelled"
                log_function_exit 1
                return 1
            fi
            ;;
        upgrade)
            log_info "Upgrade detected: v${current_version} → v${new_version}"
            ;;
        downgrade)
            log_warn "Downgrade detected: v${current_version} → v${new_version}"
            log_warn "Downgrading may cause data loss or compatibility issues"
            if ! confirm_action "Continue with downgrade?" "n"; then
                log_info "Update cancelled"
                log_function_exit 1
                return 1
            fi
            ;;
    esac

    log_function_exit 0
    return 0
}

# =============================================================================
# PRE-UPDATE BACKUP
# =============================================================================

# Create pre-update backup
create_preupdate_backup() {
    local install_path="$1"

    log_function_entry
    log_subsection "Creating Pre-Update Backup"

    log_info "Creating backup before update..."

    local backup_dir
    backup_dir=$(create_netbox_backup "$install_path" "pre-update")

    if [[ -z "$backup_dir" ]]; then
        log_error "Failed to create pre-update backup"
        log_function_exit 1
        return 1
    fi

    log_info "Pre-update backup created: $(basename "$backup_dir")"
    echo "$backup_dir"

    log_function_exit 0
    return 0
}

# =============================================================================
# UPDATE PROCESS
# =============================================================================

# Stop NetBox services for update
stop_netbox_for_update() {
    log_function_entry
    log_subsection "Stopping NetBox Services"

    local services=("netbox" "netbox-rq")

    for service in "${services[@]}"; do
        log_info "Stopping service: $service"

        if systemctl stop "$service" 2>&1 | tee -a "$LOG_FILE"; then
            log_info "Service stopped: $service"
        else
            log_warn "Failed to stop service: $service (may not be running)"
        fi
    done

    # Wait for services to stop
    sleep 2

    log_function_exit 0
    return 0
}

# Extract new NetBox version
extract_new_netbox_version() {
    local package_dir="$1"
    local install_path="$2"
    local temp_dir="$3"

    log_function_entry
    log_subsection "Extracting New NetBox Version"

    # Find NetBox tarball in package
    local netbox_tarball
    netbox_tarball=$(find "$package_dir/netbox-source" -name "netbox-*.tar.gz" -type f | head -1)

    if [[ -z "$netbox_tarball" ]]; then
        log_error "NetBox source tarball not found in update package"
        log_function_exit 1
        return 1
    fi

    log_info "Extracting new NetBox version to temporary directory..."

    # Extract to temp directory
    mkdir -p "$temp_dir"

    if tar -xzf "$netbox_tarball" -C "$temp_dir" --strip-components=1; then
        log_info "NetBox source extracted"
        log_function_exit 0
        return 0
    else
        log_error "Failed to extract NetBox source"
        log_function_exit 1
        return 1
    fi
}

# Update Python dependencies
update_python_dependencies() {
    local package_dir="$1"
    local install_path="$2"
    local temp_netbox_dir="$3"

    log_function_entry
    log_subsection "Updating Python Dependencies"

    local wheels_dir="${package_dir}/wheels"
    local venv_path="${install_path}/venv"
    local pip_cmd="${venv_path}/bin/pip"

    local requirements_file="${temp_netbox_dir}/requirements.txt"

    if [[ ! -f "$requirements_file" ]]; then
        log_error "requirements.txt not found in new NetBox version"
        log_function_exit 1
        return 1
    fi

    log_info "Upgrading Python packages..."

    # Fix #37: Redirect pip install output to log file only
    # The verbose pip output (~200 lines) was escaping to console using tee
    # Change to >> redirect to keep console clean while preserving full log
    #
    # Fix #51: Add --force-reinstall to prevent package version conflicts
    # During upgrades, --upgrade alone may leave orphaned files from old versions
    # This can cause ImportError when new packages expect different module structures
    # --force-reinstall ensures all packages are completely removed and reinstalled
    if $pip_cmd install --upgrade --force-reinstall \
        --no-index \
        --find-links="$wheels_dir" \
        -r "$requirements_file" \
        >> "$LOG_FILE" 2>&1; then

        log_info "Python dependencies updated successfully"
        log_function_exit 0
        return 0
    else
        log_error "Failed to update Python dependencies"
        log_function_exit 1
        return 1
    fi
}

# Update NetBox application files
update_netbox_files() {
    local temp_netbox_dir="$1"
    local install_path="$2"

    log_function_entry
    log_subsection "Updating NetBox Application Files"

    log_info "Backing up current configuration..."

    # Backup current configuration OUTSIDE the directory being removed
    # (Saving inside ${install_path}/netbox would delete the backup at line 303)
    local config_backup="${install_path}/configuration.py.update-backup"
    cp "${install_path}/netbox/netbox/configuration.py" "$config_backup"

    log_info "Updating NetBox application files..."

    # Remove old NetBox directory (preserve venv and configuration)
    local old_netbox="${install_path}/netbox"

    # Create backup of media and scripts directories
    if [[ -d "$old_netbox/media" ]]; then
        cp -r "$old_netbox/media" "${install_path}/media.backup"
    fi

    if [[ -d "$old_netbox/scripts" ]]; then
        cp -r "$old_netbox/scripts" "${install_path}/scripts.backup"
    fi

    # Remove old netbox directory
    rm -rf "$old_netbox"

    # Copy new NetBox version
    if cp -r "${temp_netbox_dir}/netbox" "${install_path}/netbox"; then
        log_info "NetBox files updated"
    else
        log_error "Failed to copy new NetBox files"
        log_function_exit 1
        return 1
    fi

    # Restore configuration
    log_info "Restoring configuration..."
    cp "$config_backup" "${install_path}/netbox/netbox/configuration.py"

    # Clean up configuration backup
    rm -f "$config_backup"

    # Restore media and scripts
    if [[ -d "${install_path}/media.backup" ]]; then
        cp -r "${install_path}/media.backup"/* "${install_path}/netbox/media/" 2>/dev/null
        rm -rf "${install_path}/media.backup"
    fi

    if [[ -d "${install_path}/scripts.backup" ]]; then
        cp -r "${install_path}/scripts.backup"/* "${install_path}/netbox/scripts/" 2>/dev/null
        rm -rf "${install_path}/scripts.backup"
    fi

    # Copy other important files (documentation, contrib, etc.)
    for item in contrib docs upgrade.sh; do
        if [[ -e "${temp_netbox_dir}/$item" ]]; then
            cp -r "${temp_netbox_dir}/$item" "${install_path}/"
        fi
    done

    log_function_exit 0
    return 0
}

# Run database migrations
run_update_migrations() {
    local install_path="$1"

    log_function_entry
    log_subsection "Running Database Migrations"

    local manage_py="${install_path}/netbox/manage.py"
    local python_cmd="${install_path}/venv/bin/python"

    log_info "Running database migrations..."
    log_info "This may take several minutes depending on the update size..."

    # Fix #50: Redirect Django migrate output to log file only (no console spam)
    if $python_cmd "$manage_py" migrate >> "$LOG_FILE" 2>&1; then
        log_info "Database migrations completed successfully"
        log_function_exit 0
        return 0
    else
        log_error "Database migrations failed"
        log_error "NetBox may be in an inconsistent state"
        log_error "Consider restoring from pre-update backup"
        log_function_exit 1
        return 1
    fi
}

# Clear and recollect static files
update_static_files() {
    local install_path="$1"

    log_function_entry
    log_subsection "Updating Static Files"

    local manage_py="${install_path}/netbox/manage.py"
    local python_cmd="${install_path}/venv/bin/python"

    log_info "Clearing old static files..."

    # Clear old static files
    $python_cmd "$manage_py" collectstatic --clear --no-input &>/dev/null

    log_info "Collecting new static files..."

    # Fix #50: Redirect Django collectstatic output to log file only (no console spam)
    if $python_cmd "$manage_py" collectstatic --no-input >> "$LOG_FILE" 2>&1; then
        log_info "Static files updated successfully"
        log_function_exit 0
        return 0
    else
        log_error "Failed to collect static files"
        log_function_exit 1
        return 1
    fi
}

# Remove stale content types (Django cleanup)
remove_stale_content_types() {
    local install_path="$1"

    log_function_entry

    local manage_py="${install_path}/netbox/manage.py"
    local python_cmd="${install_path}/venv/bin/python"

    log_info "Removing stale content types..."

    # Remove stale content types (non-interactive)
    echo "yes" | $python_cmd "$manage_py" remove_stale_contenttypes &>/dev/null || \
        log_debug "No stale content types to remove"

    log_function_exit 0
    return 0
}

# Clear Django cache
clear_django_cache() {
    local install_path="$1"

    log_function_entry

    local manage_py="${install_path}/netbox/manage.py"
    local python_cmd="${install_path}/venv/bin/python"

    log_info "Clearing Django cache..."

    $python_cmd "$manage_py" invalidate all &>/dev/null || \
        log_debug "Cache clear not available or failed (non-critical)"

    log_function_exit 0
    return 0
}

# Start NetBox services after update
start_netbox_after_update() {
    log_function_entry
    log_subsection "Starting NetBox Services"

    local services=("netbox" "netbox-rq")

    for service in "${services[@]}"; do
        log_info "Starting service: $service"

        if systemctl start "$service" 2>&1 | tee -a "$LOG_FILE"; then
            log_info "Service started: $service"
        else
            log_error "Failed to start service: $service"
            log_function_exit 1
            return 1
        fi
    done

    # Wait for services to start
    sleep 3

    # Verify services are running
    local all_running=true
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            log_info "✓ $service is active"
        else
            log_error "✗ $service failed to start"
            systemctl status "$service" | tee -a "$LOG_FILE"
            all_running=false
        fi
    done

    if [[ "$all_running" == "true" ]]; then
        log_function_exit 0
        return 0
    else
        log_error "Some services failed to start"
        log_function_exit 1
        return 1
    fi
}

# Verify updated installation
verify_update() {
    local install_path="$1"
    local expected_version="$2"

    log_function_entry
    log_subsection "Verifying Update"

    # Check installed version
    local installed_version
    installed_version=$(get_installed_netbox_version "$install_path")

    if [[ "$installed_version" == "$expected_version" ]]; then
        log_info "✓ Version verification passed: v${installed_version}"
    else
        log_error "✗ Version mismatch: expected v${expected_version}, found v${installed_version}"
        log_function_exit 1
        return 1
    fi

    # Check service status
    for service in netbox netbox-rq; do
        if systemctl is-active --quiet "$service"; then
            log_info "✓ $service is running"
        else
            log_error "✗ $service is not running"
            log_function_exit 1
            return 1
        fi
    done

    # Test HTTP connectivity
    if curl -k -s -o /dev/null -w "%{http_code}" "http://localhost" | grep -q "200\|301\|302"; then
        log_info "✓ HTTP connectivity successful"
    else
        log_warn "HTTP connectivity test inconclusive"
    fi

    log_info "Update verification complete"
    log_function_exit 0
    return 0
}

# =============================================================================
# MAIN UPDATE ORCHESTRATION
# =============================================================================

# Perform NetBox update from offline package
update_netbox() {
    local package_dir="$1"
    local install_path="${2:-${INSTALL_PATH:-/opt/netbox}}"

    log_function_entry
    log_section "NetBox Update"

    # Pre-flight checks
    check_root_user

    # Validate installation exists
    if [[ ! -d "$install_path" ]]; then
        log_error "NetBox installation not found: $install_path"
        log_function_exit 1
        return 1
    fi

    # Get versions
    local current_version new_version
    current_version=$(get_installed_netbox_version "$install_path")
    new_version=$(get_package_netbox_version "$package_dir")

    log_info "NetBox Update: v${current_version} → v${new_version}"

    # Validate update package
    validate_update_package "$package_dir" "$install_path" || {
        log_error "Update package validation failed"
        log_function_exit 1
        return 1
    }

    # Create VM snapshot (optional)
    if [[ "${VM_SNAPSHOT_ENABLED:-yes}" == "yes" ]]; then
        create_vm_snapshot_safe "netbox-pre-update-${new_version}"
    fi

    # Create pre-update backup
    local backup_dir
    backup_dir=$(create_preupdate_backup "$install_path") || {
        log_error "Failed to create pre-update backup"

        if ! confirm_action "Continue without backup?" "n"; then
            log_info "Update cancelled"
            log_function_exit 1
            return 1
        fi
    }

    # Create temporary directory for new version
    local temp_dir="/tmp/netbox-update-$$"
    mkdir -p "$temp_dir"

    # Stop services
    stop_netbox_for_update || {
        log_error "Failed to stop NetBox services"
        log_function_exit 1
        return 1
    }

    # Extract new version
    extract_new_netbox_version "$package_dir" "$install_path" "$temp_dir" || {
        log_error "Failed to extract new NetBox version"
        log_function_exit 1
        return 1
    }

    # Update Python dependencies
    update_python_dependencies "$package_dir" "$install_path" "$temp_dir" || {
        log_error "Failed to update Python dependencies"
        log_error "Attempting to restore from backup..."
        restore_from_backup "$(basename "$backup_dir")" "$install_path"
        log_function_exit 1
        return 1
    }

    # Update NetBox files
    update_netbox_files "$temp_dir" "$install_path" || {
        log_error "Failed to update NetBox files"
        log_error "Attempting to restore from backup..."
        restore_from_backup "$(basename "$backup_dir")" "$install_path"
        log_function_exit 1
        return 1
    }

    # Run database migrations
    run_update_migrations "$install_path" || {
        log_error "Database migrations failed"
        log_error "CRITICAL: System may be in inconsistent state"
        log_error "Manual intervention may be required"
        log_error "Backup available at: $backup_dir"
        log_function_exit 1
        return 1
    }

    # Update static files
    update_static_files "$install_path" || {
        log_warn "Static file collection had issues (non-critical)"
    }

    # Cleanup tasks
    remove_stale_content_types "$install_path"
    clear_django_cache "$install_path"

    # Set permissions
    log_subsection "Setting Permissions"
    set_secure_permissions "$install_path" "netbox" "netbox" "NetBox Update"

    # Start services
    start_netbox_after_update || {
        log_error "Services failed to start after update"
        log_error "Check logs and consider restoring from backup"
        log_function_exit 1
        return 1
    }

    # Verify update
    verify_update "$install_path" "$new_version" || {
        log_error "Update verification failed"
        log_warn "NetBox may not be functioning correctly"
    }

    # Cleanup temp directory
    rm -rf "$temp_dir"

    # Update complete
    log_success_summary "NetBox Update"
    log_info "NetBox updated successfully!"
    log_info "Previous version: v${current_version}"
    log_info "Current version:  v${new_version}"
    log_info "Pre-update backup: $backup_dir"
    log_security "NetBox updated: v${current_version} → v${new_version}"

    echo
    echo "================================================================================"
    echo "NetBox Update Complete"
    echo "================================================================================"
    echo "Previous Version: v${current_version}"
    echo "Current Version:  v${new_version}"
    echo
    echo "Pre-Update Backup: $(basename "$backup_dir")"
    echo
    echo "If you experience any issues, you can rollback using:"
    echo "  ./netbox-installer.sh rollback -b $(basename "$backup_dir")"
    echo
    echo "================================================================================"
    echo

    log_function_exit 0
    return 0
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize update module
init_update() {
    log_debug "Update module initialized"
}

# Auto-initialize when sourced
init_update

# End of update.sh
