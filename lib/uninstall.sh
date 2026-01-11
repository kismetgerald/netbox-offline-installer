#!/bin/bash
#
# NetBox Offline Installer - Uninstall Module
# Version: 0.0.1
# Description: Complete NetBox removal with optional backup preservation
#
# Created by: Kismet Agbasi (KismetG17@gmail.com)
# AI Collaborator: Claude Code (integrated with VS Code)
# Date Created: 12/27/2025
# Last Updated: 01/11/2026
#
# This module performs complete NetBox uninstallation:
# - Optional final backup creation
# - Stop and disable all services
# - Remove systemd service files
# - Drop PostgreSQL database and user
# - Remove installation directory
# - Remove system user
# - Remove Nginx configuration
# - Clean up SELinux/FAPolicyD rules
# - Optional backup deletion (default: delete with confirmation)
#

# =============================================================================
# UNINSTALL VALIDATION
# =============================================================================

# Verify NetBox installation exists
verify_installation_exists() {
    local install_path="$1"

    log_function_entry

    if [[ ! -d "$install_path" ]]; then
        log_warn "NetBox installation not found: $install_path"
        log_function_exit 1
        return 1
    fi

    if [[ ! -f "$install_path/netbox/netbox/configuration.py" ]]; then
        log_warn "NetBox configuration not found (partial installation?)"
    fi

    log_function_exit 0
    return 0
}

# Get installation details for confirmation
get_installation_details() {
    local install_path="$1"

    log_function_entry

    echo
    echo "================================================================================"
    echo "NetBox Installation Details"
    echo "================================================================================"

    # Version
    local version
    version=$(get_installed_netbox_version "$install_path" 2>/dev/null || echo "unknown")
    echo "Version:          v${version}"

    # Installation path
    echo "Install Path:     $install_path"

    # Installation size
    local install_size
    install_size=$(du -sh "$install_path" 2>/dev/null | awk '{print $1}' || echo "unknown")
    echo "Size:             $install_size"

    # Services
    echo
    echo "Services:"
    for service in netbox netbox-rq nginx postgresql-16 redis; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo "  $service: running"
        elif systemctl is-enabled --quiet "$service" 2>/dev/null; then
            echo "  $service: stopped (enabled)"
        else
            echo "  $service: not installed"
        fi
    done

    # Database
    if [[ -f "$install_path/netbox/netbox/configuration.py" ]]; then
        echo
        echo "Database:"
        local db_name
        db_name=$(grep -oP "NAME.*['\"]\\K[^'\"]*" \
            "$install_path/netbox/netbox/configuration.py" 2>/dev/null | head -1 || echo "unknown")
        echo "  Name:           $db_name"
    fi

    # Backups
    local backup_dir="${BACKUP_DIR:-/var/backup/netbox-offline-installer}"
    if [[ -d "$backup_dir" ]]; then
        local backup_count
        backup_count=$(find "$backup_dir" -maxdepth 1 -type d -name "backup-*" 2>/dev/null | wc -l)
        echo
        echo "Backups:          $backup_count available"
    fi

    echo "================================================================================"
    echo

    log_function_exit 0
    return 0
}

# =============================================================================
# SERVICE CLEANUP
# =============================================================================

# Stop and disable NetBox services
stop_and_disable_services() {
    log_function_entry
    log_subsection "Stopping and Disabling Services"

    local services=("netbox" "netbox-rq")

    for service in "${services[@]}"; do
        log_info "Stopping and disabling: $service"

        # Stop service
        systemctl stop "$service" 2>&1 | tee -a "$LOG_FILE" || \
            log_debug "Service not running or doesn't exist: $service"

        # Disable service
        systemctl disable "$service" 2>&1 | tee -a "$LOG_FILE" || \
            log_debug "Service not enabled or doesn't exist: $service"
    done

    log_function_exit 0
    return 0
}

# Remove systemd service files
remove_service_files() {
    log_function_entry
    log_subsection "Removing Systemd Service Files"

    local service_files=(
        "/etc/systemd/system/netbox.service"
        "/etc/systemd/system/netbox-rq.service"
    )

    for service_file in "${service_files[@]}"; do
        if [[ -f "$service_file" ]]; then
            log_info "Removing: $service_file"
            rm -f "$service_file"
        else
            log_debug "Service file not found: $service_file"
        fi
    done

    # Reload systemd
    log_info "Reloading systemd daemon..."
    systemctl daemon-reload

    log_function_exit 0
    return 0
}

# =============================================================================
# DATABASE CLEANUP
# =============================================================================

# Drop PostgreSQL database and user
cleanup_database() {
    local install_path="$1"

    log_function_entry
    log_subsection "Cleaning Up Database"

    # Get database details from configuration
    local db_name db_user

    if [[ -f "$install_path/netbox/netbox/configuration.py" ]]; then
        db_name=$(grep -oP "NAME.*['\"]\\K[^'\"]*" \
            "$install_path/netbox/netbox/configuration.py" 2>/dev/null | head -1)
        db_user=$(grep -oP "USER.*['\"]\\K[^'\"]*" \
            "$install_path/netbox/netbox/configuration.py" 2>/dev/null | head -1)
    fi

    db_name="${db_name:-netbox}"
    db_user="${db_user:-netbox}"

    log_info "Dropping database: $db_name"

    # Drop database
    if sudo -u postgres psql -c "DROP DATABASE IF EXISTS ${db_name};" 2>&1 | tee -a "$LOG_FILE"; then
        log_info "Database dropped: $db_name"
        log_security "PostgreSQL database deleted: $db_name"
    else
        log_warn "Failed to drop database (may not exist or insufficient permissions)"
    fi

    log_info "Dropping user: $db_user"

    # Drop user
    if sudo -u postgres psql -c "DROP USER IF EXISTS ${db_user};" 2>&1 | tee -a "$LOG_FILE"; then
        log_info "User dropped: $db_user"
        log_security "PostgreSQL user deleted: $db_user"
    else
        log_warn "Failed to drop user (may not exist or insufficient permissions)"
    fi

    log_function_exit 0
    return 0
}

# =============================================================================
# FILE SYSTEM CLEANUP
# =============================================================================

# Remove installation directory
remove_installation_directory() {
    local install_path="$1"

    log_function_entry
    log_subsection "Removing Installation Directory"

    if [[ ! -d "$install_path" ]]; then
        log_info "Installation directory not found (already removed?)"
        log_function_exit 0
        return 0
    fi

    log_info "Removing installation directory: $install_path"
    log_warn "This will permanently delete all NetBox files"

    # Final confirmation
    if ! confirm_action "Confirm deletion of $install_path?" "n"; then
        log_info "Installation directory removal cancelled"
        log_function_exit 1
        return 1
    fi

    # Remove directory
    if rm -rf "$install_path"; then
        log_info "Installation directory removed"
        log_security "NetBox installation directory deleted: $install_path"
        log_function_exit 0
        return 0
    else
        log_error "Failed to remove installation directory"
        log_function_exit 1
        return 1
    fi
}

# Remove NetBox system user
remove_system_user() {
    log_function_entry
    log_subsection "Removing System User"

    local username="netbox"

    if ! id "$username" &>/dev/null; then
        log_info "System user not found (already removed?)"
        log_function_exit 0
        return 0
    fi

    log_info "Removing system user: $username"

    if userdel "$username" 2>&1 | tee -a "$LOG_FILE"; then
        log_info "System user removed: $username"
        log_security "System user deleted: $username"
    else
        log_warn "Failed to remove system user (may be in use)"
    fi

    # Remove home directory if it exists
    if [[ -d "/home/$username" ]]; then
        rm -rf "/home/$username"
    fi

    log_function_exit 0
    return 0
}

# =============================================================================
# NGINX CLEANUP
# =============================================================================

# Remove Nginx configuration
remove_nginx_configuration() {
    log_function_entry
    log_subsection "Removing Nginx Configuration"

    local nginx_conf="/etc/nginx/conf.d/netbox.conf"

    if [[ -f "$nginx_conf" ]]; then
        log_info "Removing Nginx configuration: $nginx_conf"

        rm -f "$nginx_conf"

        # Test and reload Nginx
        if nginx -t 2>&1 | tee -a "$LOG_FILE"; then
            log_info "Reloading Nginx..."
            systemctl reload nginx 2>&1 | tee -a "$LOG_FILE" || \
                log_warn "Failed to reload Nginx (may not be running)"
        else
            log_warn "Nginx configuration test failed after removal"
        fi
    else
        log_info "Nginx configuration not found (already removed?)"
    fi

    # Remove SSL certificates if self-signed
    local ssl_cert="/etc/pki/tls/certs/netbox-selfsigned.crt"
    local ssl_key="/etc/pki/tls/private/netbox-selfsigned.key"

    if [[ -f "$ssl_cert" ]]; then
        log_info "Removing self-signed certificate..."
        rm -f "$ssl_cert"
    fi

    if [[ -f "$ssl_key" ]]; then
        rm -f "$ssl_key"
    fi

    log_function_exit 0
    return 0
}

# =============================================================================
# SECURITY CLEANUP
# =============================================================================

# Remove SELinux file contexts
remove_selinux_contexts() {
    local install_path="$1"

    log_function_entry

    if ! is_selinux_installed; then
        log_debug "SELinux not installed, skipping context removal"
        log_function_exit 0
        return 0
    fi

    log_subsection "Removing SELinux Contexts"

    log_info "Removing SELinux file contexts..."

    # Remove custom file contexts
    local contexts=(
        "${install_path}/netbox/static(/.*)?"
        "${install_path}/netbox/media(/.*)?"
        "${install_path}/netbox/scripts(/.*)?"
    )

    for context in "${contexts[@]}"; do
        semanage fcontext -d -t httpd_sys_content_t "$context" 2>&1 | tee -a "$LOG_FILE" || \
            log_debug "Context not found or already removed: $context"
    done

    log_function_exit 0
    return 0
}

# Remove FAPolicyD rules
remove_fapolicyd_rules() {
    local install_path="$1"

    log_function_entry

    if ! is_fapolicyd_active; then
        log_debug "FAPolicyD not active, skipping rule removal"
        log_function_exit 0
        return 0
    fi

    log_subsection "Removing FAPolicyD Rules"

    local rules_file="/etc/fapolicyd/rules.d/50-netbox.rules"

    if [[ -f "$rules_file" ]]; then
        log_info "Removing FAPolicyD rules: $rules_file"

        rm -f "$rules_file"

        # Reload FAPolicyD
        log_info "Reloading FAPolicyD..."
        systemctl reload fapolicyd 2>&1 | tee -a "$LOG_FILE" || \
            log_warn "Failed to reload FAPolicyD"
    else
        log_debug "FAPolicyD rules file not found"
    fi

    # Remove trusted paths (if possible)
    fapolicyd-cli --file delete "$install_path" 2>&1 | tee -a "$LOG_FILE" || \
        log_debug "Failed to remove FAPolicyD trusted path"

    log_function_exit 0
    return 0
}

# =============================================================================
# BACKUP CLEANUP
# =============================================================================

# Remove all backups
remove_all_backups() {
    log_function_entry
    log_subsection "Removing Backups"

    local backup_dir="${BACKUP_DIR:-/var/backup/netbox-offline-installer}"

    if [[ ! -d "$backup_dir" ]]; then
        log_info "Backup directory not found (no backups to remove)"
        log_function_exit 0
        return 0
    fi

    # Count backups
    local backup_count
    backup_count=$(find "$backup_dir" -maxdepth 1 -type d -name "backup-*" 2>/dev/null | wc -l)

    if [[ $backup_count -eq 0 ]]; then
        log_info "No backups found"
        # Remove empty backup directory
        rmdir "$backup_dir" 2>/dev/null
        log_function_exit 0
        return 0
    fi

    log_info "Found $backup_count backup(s)"

    # Calculate total backup size
    local total_size
    total_size=$(du -sh "$backup_dir" 2>/dev/null | awk '{print $1}')
    log_info "Total backup size: $total_size"

    log_warn "Removing all backups will permanently delete:"
    log_warn "  - $backup_count backup(s)"
    log_warn "  - $total_size of data"

    if confirm_action "Delete all backups?" "n"; then
        log_info "Removing backup directory: $backup_dir"

        if rm -rf "$backup_dir"; then
            log_info "All backups removed"
            log_security "All NetBox backups deleted"
        else
            log_error "Failed to remove backup directory"
            log_function_exit 1
            return 1
        fi
    else
        log_info "Backups preserved at: $backup_dir"
    fi

    log_function_exit 0
    return 0
}

# =============================================================================
# FINAL BACKUP
# =============================================================================

# Create final backup before uninstall
create_final_backup() {
    local install_path="$1"

    log_function_entry
    log_subsection "Final Backup Creation"

    log_info "Creating final backup before uninstall..."
    log_info "This backup can be used if you need to reinstall NetBox later"

    if ! confirm_action "Create final backup?" "y"; then
        log_info "Skipping final backup"
        log_function_exit 0
        return 0
    fi

    local backup_dir
    backup_dir=$(create_netbox_backup "$install_path" "final-pre-uninstall")

    if [[ -n "$backup_dir" ]]; then
        log_info "Final backup created: $(basename "$backup_dir")"
        log_info "Backup location: $backup_dir"
        echo "$backup_dir"
    else
        log_warn "Failed to create final backup"
    fi

    log_function_exit 0
    return 0
}

# =============================================================================
# UNINSTALL SUMMARY
# =============================================================================

# Display uninstall summary
display_uninstall_summary() {
    local install_path="$1"
    local removed_components="$2"

    log_section "Uninstall Summary"

    echo
    echo "================================================================================"
    echo "NetBox Uninstall Summary"
    echo "================================================================================"
    echo
    echo "Removed Components:"
    echo "$removed_components"
    echo
    echo "================================================================================"
    echo

    log_function_exit 0
    return 0
}

# =============================================================================
# MAIN UNINSTALL ORCHESTRATION
# =============================================================================

# Perform complete NetBox uninstallation
uninstall_netbox() {
    local install_path="${1:-${INSTALL_PATH:-/opt/netbox}}"

    log_function_entry
    log_section "NetBox Uninstallation"

    # Pre-flight checks
    check_root_user

    # Verify installation exists
    if ! verify_installation_exists "$install_path"; then
        log_warn "NetBox installation not found or incomplete"

        if ! confirm_action "Continue with cleanup anyway?" "n"; then
            log_info "Uninstall cancelled"
            log_function_exit 0
            return 0
        fi
    fi

    # Display installation details
    get_installation_details "$install_path"

    # Final confirmation
    echo
    log_warn "This will PERMANENTLY REMOVE NetBox and all associated data!"
    log_warn "Database, configuration, and media files will be deleted!"
    echo

    if ! confirm_action "Are you absolutely sure you want to uninstall NetBox?" "n"; then
        log_info "Uninstall cancelled by user"
        log_function_exit 0
        return 0
    fi

    # Double confirmation
    echo
    if ! confirm_action "Type 'yes' to confirm uninstallation" "no"; then
        log_info "Uninstall cancelled (confirmation failed)"
        log_function_exit 0
        return 0
    fi

    # Create final backup (optional)
    local final_backup
    final_backup=$(create_final_backup "$install_path")

    # Track removed components
    local removed_components=""

    # Stop and disable services
    stop_and_disable_services
    removed_components+="  ✓ NetBox services stopped and disabled\n"

    # Remove service files
    remove_service_files
    removed_components+="  ✓ Systemd service files removed\n"

    # Cleanup database
    cleanup_database "$install_path"
    removed_components+="  ✓ PostgreSQL database and user removed\n"

    # Remove Nginx configuration
    remove_nginx_configuration
    removed_components+="  ✓ Nginx configuration removed\n"

    # Remove security configurations
    remove_selinux_contexts "$install_path"
    remove_fapolicyd_rules "$install_path"
    removed_components+="  ✓ SELinux/FAPolicyD rules cleaned\n"

    # Remove installation directory
    if remove_installation_directory "$install_path"; then
        removed_components+="  ✓ Installation directory removed\n"
    else
        removed_components+="  ✗ Installation directory removal failed\n"
    fi

    # Remove system user
    remove_system_user
    removed_components+="  ✓ System user removed\n"

    # Handle backups
    echo
    log_subsection "Backup Cleanup"

    log_info "By default, all backups will be deleted during uninstall"

    if [[ -n "$final_backup" ]]; then
        log_info "Final backup was created at: $final_backup"
        log_info "You may want to preserve this backup before deleting all backups"
    fi

    remove_all_backups

    # Display summary
    display_uninstall_summary "$install_path" "$(echo -e "$removed_components")"

    log_success_summary "NetBox Uninstallation"
    log_info "NetBox has been completely removed from the system"
    log_security "NetBox uninstalled from: $install_path"

    echo "================================================================================"
    echo "NetBox Uninstallation Complete"
    echo "================================================================================"
    echo
    echo "All NetBox components have been removed from the system."
    echo

    if [[ -n "$final_backup" && -d "$final_backup" ]]; then
        echo "A final backup was preserved at:"
        echo "  $final_backup"
        echo
        echo "If you need to reinstall NetBox, you can restore from this backup using:"
        echo "  ./netbox-installer.sh rollback -b $(basename "$final_backup")"
        echo
    fi

    echo "Services that may still be running (not removed by uninstaller):"
    echo "  - PostgreSQL (may be used by other applications)"
    echo "  - Redis (may be used by other applications)"
    echo "  - Nginx (may be serving other sites)"
    echo
    echo "If these services are no longer needed, you can remove them manually."
    echo "================================================================================"
    echo

    log_function_exit 0
    return 0
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize uninstall module
init_uninstall() {
    log_debug "Uninstall module initialized"
}

# Auto-initialize when sourced
init_uninstall

# End of uninstall.sh
