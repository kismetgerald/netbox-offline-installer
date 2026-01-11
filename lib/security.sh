#!/bin/bash
#
# NetBox Offline Installer - Security Hardening
# Version: 0.0.1
# Description: SELinux, FAPolicyD configuration, and file permissions
#
# Created by: Kismet Agbasi (KismetG17@gmail.com)
# AI Collaborator: Claude Code (integrated with VS Code)
# Date Created: 12/27/2025
# Last Updated: 01/11/2026
#

# =============================================================================
# SELINUX DETECTION AND CONFIGURATION
# =============================================================================

# Check if SELinux is installed
is_selinux_installed() {
    # Check for SELinux binaries or filesystem
    if [[ -x /usr/sbin/selinuxenabled ]] || [[ -d /sys/fs/selinux ]]; then
        return 0
    fi
    return 1
}

# Get current SELinux mode
get_selinux_mode() {
    if ! is_selinux_installed; then
        echo "not-installed"
        return 1
    fi

    if command -v getenforce &>/dev/null; then
        getenforce 2>/dev/null || echo "unknown"
    else
        echo "unknown"
    fi
}

# Check if SELinux is enforcing
is_selinux_enforcing() {
    local mode
    mode=$(get_selinux_mode)
    [[ "$mode" == "Enforcing" ]]
}

# Apply SELinux file contexts for NetBox
apply_selinux_contexts() {
    local install_path="$1"

    if ! is_selinux_installed; then
        log_info "SELinux not installed, skipping context configuration"
        return 0
    fi

    log_section "Configuring SELinux Contexts"

    local current_mode
    current_mode=$(get_selinux_mode)
    log_info "Current SELinux mode: $current_mode"

    # Check if semanage is available
    if ! command -v semanage &>/dev/null; then
        log_warn "semanage command not found (install policycoreutils-python-utils)"
        log_warn "Skipping SELinux file context configuration"
        return 1
    fi

    # Apply file contexts for static files (served by nginx)
    log_info "Setting context for static files..."
    if semanage fcontext -a -t httpd_sys_content_t "${install_path}/netbox/static(/.*)?" >> "$LOG_FILE" 2>&1; then
        log_info "Added httpd_sys_content_t context for static files"
    else
        # Context might already exist, try to modify
        if semanage fcontext -m -t httpd_sys_content_t "${install_path}/netbox/static(/.*)?" >> "$LOG_FILE" 2>&1; then
            log_debug "Modified existing httpd_sys_content_t context for static files"
        else
            log_debug "Static file context already configured"
        fi
    fi

    # Apply file contexts for media files (read/write by nginx and netbox)
    log_info "Setting context for media files..."
    if semanage fcontext -a -t httpd_sys_rw_content_t "${install_path}/netbox/media(/.*)?" >> "$LOG_FILE" 2>&1; then
        log_info "Added httpd_sys_rw_content_t context for media files"
    else
        if semanage fcontext -m -t httpd_sys_rw_content_t "${install_path}/netbox/media(/.*)?" >> "$LOG_FILE" 2>&1; then
            log_debug "Modified existing httpd_sys_rw_content_t context for media files"
        else
            log_debug "Media file context already configured"
        fi
    fi

    # Apply file contexts for scripts
    log_info "Setting context for script files..."
    if semanage fcontext -a -t httpd_sys_script_exec_t "${install_path}/netbox/scripts(/.*)?" >> "$LOG_FILE" 2>&1; then
        log_info "Added httpd_sys_script_exec_t context for scripts"
    else
        if semanage fcontext -m -t httpd_sys_script_exec_t "${install_path}/netbox/scripts(/.*)?" >> "$LOG_FILE" 2>&1; then
            log_debug "Modified existing httpd_sys_script_exec_t context for scripts"
        else
            log_debug "Script file context already configured"
        fi
    fi

    # Apply file contexts for reports
    log_info "Setting context for report files..."
    if semanage fcontext -a -t httpd_sys_rw_content_t "${install_path}/netbox/reports(/.*)?" >> "$LOG_FILE" 2>&1; then
        log_info "Added httpd_sys_rw_content_t context for reports"
    else
        if semanage fcontext -m -t httpd_sys_rw_content_t "${install_path}/netbox/reports(/.*)?" >> "$LOG_FILE" 2>&1; then
            log_debug "Modified existing httpd_sys_rw_content_t context for reports"
        else
            log_debug "Report file context already configured"
        fi
    fi

    # Apply file contexts for Python virtual environment binaries
    log_info "Setting context for Python virtual environment binaries..."
    if semanage fcontext -a -t bin_t "${install_path}/venv/bin(/.*)?" >> "$LOG_FILE" 2>&1; then
        log_info "Added bin_t context for venv binaries"
    else
        if semanage fcontext -m -t bin_t "${install_path}/venv/bin(/.*)?" >> "$LOG_FILE" 2>&1; then
            log_debug "Modified existing bin_t context for venv binaries"
        else
            log_debug "Virtual environment binary context already configured"
        fi
    fi

    # Restore file contexts
    log_info "Applying SELinux contexts to files..."
    if ! restorecon -R -v "$install_path" 2>&1 | head -20 | while read -r line; do log_debug "$line"; done; then
        log_warn "restorecon completed with warnings"
    fi

    log_security "SELinux file contexts applied for $install_path"
    return 0
}

# Set SELinux booleans for NetBox
set_selinux_booleans() {
    if ! is_selinux_installed; then
        log_info "SELinux not installed, skipping boolean configuration"
        return 0
    fi

    log_subsection "Configuring SELinux Booleans"

    # Check if setsebool is available
    if ! command -v setsebool &>/dev/null; then
        log_warn "setsebool command not found"
        return 1
    fi

    # Allow nginx to connect to network (for gunicorn)
    log_info "Enabling httpd_can_network_connect..."
    if setsebool -P httpd_can_network_connect 1; then
        log_security "Enabled httpd_can_network_connect (nginx → gunicorn)"
    else
        log_warn "Failed to set httpd_can_network_connect"
    fi

    # Allow nginx to connect to database (for remote Redis)
    log_info "Enabling httpd_can_network_connect_db..."
    if setsebool -P httpd_can_network_connect_db 1; then
        log_security "Enabled httpd_can_network_connect_db (nginx → redis)"
    else
        log_warn "Failed to set httpd_can_network_connect_db"
    fi

    return 0
}

# Apply SELinux context for SSL certificates
apply_ssl_cert_context() {
    local cert_path="$1"
    local key_path="$2"

    if ! is_selinux_installed; then
        return 0
    fi

    if [[ -f "$cert_path" ]]; then
        log_debug "Setting SELinux context for SSL certificate: $cert_path"
        chcon -t httpd_sys_content_t "$cert_path" 2>/dev/null || \
            log_debug "Failed to set context for certificate"
    fi

    if [[ -f "$key_path" ]]; then
        log_debug "Setting SELinux context for SSL key: $key_path"
        chcon -t httpd_sys_content_t "$key_path" 2>/dev/null || \
            log_debug "Failed to set context for key"
    fi
}

# Configure SELinux for NetBox
configure_selinux() {
    local install_path="$1"
    local enable_mode="${ENABLE_SELINUX:-auto}"

    log_function_entry

    case "$enable_mode" in
        auto)
            if ! is_selinux_installed; then
                log_info "SELinux not installed, skipping configuration"
                return 0
            fi
            ;;
        yes)
            if ! is_selinux_installed; then
                log_error "SELinux configuration required but SELinux not installed"
                return 1
            fi
            ;;
        no)
            log_info "SELinux configuration disabled by user"
            return 0
            ;;
        *)
            log_error "Invalid ENABLE_SELINUX value: $enable_mode"
            return 1
            ;;
    esac

    # Display current SELinux status
    local current_mode
    current_mode=$(get_selinux_mode)

    log_info "Configuring SELinux for NetBox installation"
    log_info "Current SELinux mode: $current_mode"

    if [[ "$current_mode" != "Enforcing" ]]; then
        log_warn "SELinux is not in Enforcing mode"
        log_warn "Contexts will be applied for future compatibility"
        log_warn "Recommended: Enable Enforcing mode for production"
    fi

    # Apply file contexts
    apply_selinux_contexts "$install_path" || return 1

    # Set booleans
    set_selinux_booleans || return 1

    log_success_summary "SELinux Configuration"
    log_function_exit 0
    return 0
}

# =============================================================================
# FAPOLICYD DETECTION AND CONFIGURATION
# =============================================================================

# Check if FAPolicyD is installed and active
is_fapolicyd_active() {
    if ! command -v fapolicyd &>/dev/null; then
        return 1
    fi

    systemctl is-active --quiet fapolicyd 2>/dev/null
}

# Add path to FAPolicyD trust
add_fapolicyd_trust() {
    local path="$1"

    if ! command -v fapolicyd-cli &>/dev/null; then
        log_warn "fapolicyd-cli not found, cannot add trust"
        return 1
    fi

    log_info "Adding to FAPolicyD trust: $path"

    # Capture output and check for specific error messages
    local output
    output=$(fapolicyd-cli --file add "$path" 2>&1)
    local exit_code=$?

    # Log output to file
    echo "$output" >> "$LOG_FILE"

    # Check if path is already trusted (not an error)
    if echo "$output" | grep -q "After removing duplicates, there is nothing to add"; then
        log_debug "$path already in FAPolicyD trust database"
        return 0
    elif [[ $exit_code -eq 0 ]]; then
        log_security "Added $path to FAPolicyD trust database"
        return 0
    else
        log_warn "Failed to add $path to FAPolicyD trust"
        log_debug "FAPolicyD output: $output"
        return 1
    fi
}

# Update FAPolicyD trust database
update_fapolicyd_trust() {
    if ! command -v fapolicyd-cli &>/dev/null; then
        return 1
    fi

    log_info "Updating FAPolicyD trust database..."

    if fapolicyd-cli --update >> "$LOG_FILE" 2>&1; then
        log_info "FAPolicyD trust database updated"
        return 0
    else
        log_warn "Failed to update FAPolicyD trust database"
        return 1
    fi
}

# Create FAPolicyD custom rules
create_fapolicyd_rules() {
    local install_path="$1"
    local python_bin="$2"
    local rules_file="/etc/fapolicyd/rules.d/50-netbox.rules"

    log_info "Creating FAPolicyD custom rules: $rules_file"

    # Create rules directory if it doesn't exist
    mkdir -p "$(dirname "$rules_file")"

    # Create custom rules file
    cat > "$rules_file" <<EOF
# NetBox Offline Installer - FAPolicyD Rules
# Generated: $(date '+%Y-%m-%d %H:%M:%S')

# Allow execution from NetBox installation directory
allow perm=any all : trust=1 path=${install_path}

# Allow Python interpreter
allow perm=execute all : trust=1 path=${python_bin}

# Allow Gunicorn and related Python processes
allow perm=execute all : trust=1 path=${install_path}/venv/bin/

# End of NetBox rules
EOF

    chmod 644 "$rules_file"
    log_security "Created FAPolicyD rules: $rules_file"

    return 0
}

# Reload FAPolicyD
reload_fapolicyd() {
    if ! systemctl is-active --quiet fapolicyd; then
        log_info "FAPolicyD not running, skipping reload"
        return 0
    fi

    log_info "Restarting FAPolicyD..."

    # FAPolicyD doesn't support reload, must use restart
    if systemctl restart fapolicyd >> "$LOG_FILE" 2>&1; then
        log_security "FAPolicyD restarted successfully"
        return 0
    else
        log_error "Failed to restart FAPolicyD"
        return 1
    fi
}

# Configure FAPolicyD for NetBox
configure_fapolicyd() {
    local install_path="$1"
    local enable_mode="${ENABLE_FAPOLICYD:-auto}"

    log_function_entry

    case "$enable_mode" in
        auto)
            if ! is_fapolicyd_active; then
                log_info "FAPolicyD not active, skipping configuration"
                return 0
            fi
            ;;
        yes)
            if ! is_fapolicyd_active; then
                log_error "FAPolicyD configuration required but FAPolicyD not active"
                return 1
            fi
            ;;
        no)
            log_info "FAPolicyD configuration disabled by user"
            return 0
            ;;
        *)
            log_error "Invalid ENABLE_FAPOLICYD value: $enable_mode"
            return 1
            ;;
    esac

    log_section "Configuring FAPolicyD"

    # Detect Python binary
    local python_bin
    python_bin=$(command -v python3.12 2>/dev/null || \
                 command -v python3.11 2>/dev/null || \
                 command -v python3 2>/dev/null)

    if [[ -z "$python_bin" ]]; then
        log_error "Python binary not found"
        return 1
    fi

    log_info "Python binary: $python_bin"

    # Add NetBox installation to trust
    add_fapolicyd_trust "$install_path"

    # Add Python binary to trust
    add_fapolicyd_trust "$python_bin"

    # Create custom rules
    create_fapolicyd_rules "$install_path" "$python_bin" || return 1

    # Update trust database
    update_fapolicyd_trust || return 1

    # Reload FAPolicyD
    reload_fapolicyd || return 1

    log_success_summary "FAPolicyD Configuration"
    log_function_exit 0
    return 0
}

# =============================================================================
# FILE PERMISSIONS AND OWNERSHIP
# =============================================================================

# Create system user for NetBox
create_netbox_user() {
    local username="${1:-netbox}"
    local home_dir="${2:-/opt/netbox}"

    log_subsection "Creating NetBox System User"

    # Check if user already exists
    if id -u "$username" &>/dev/null; then
        log_info "User $username already exists"

        # Ensure user is in the netbox group (in case it was created separately)
        if getent group "$username" &>/dev/null; then
            # Check if user is already in the group
            if id -nG "$username" | grep -qw "$username"; then
                log_info "User $username is already in group $username"
            else
                log_info "Adding user $username to group $username"
                if usermod -a -G "$username" "$username"; then
                    log_info "User $username added to group $username"
                else
                    log_warn "Failed to add user $username to group $username"
                fi
            fi
        fi
        return 0
    fi

    log_info "Creating system user: $username"

    # Check if group already exists (e.g., created by PostgreSQL)
    # Build useradd command with proper quoting and redirect output to log
    if getent group "$username" &>/dev/null; then
        log_info "Group $username already exists, using existing group"
        # Use existing group instead of creating a new one
        if useradd -r -s /bin/bash -d "$home_dir" -c "NetBox Application User" -g "$username" "$username" >> "$LOG_FILE" 2>&1; then
            log_security "Created system user: $username"
            log_audit "User created: $username (home: $home_dir)"
            return 0
        else
            log_error "Failed to create user: $username"
            log_error "Check log file for details: $LOG_FILE"
            return 1
        fi
    else
        # Group doesn't exist, create both user and group
        if useradd -r -s /bin/bash -d "$home_dir" -c "NetBox Application User" "$username" >> "$LOG_FILE" 2>&1; then
            log_security "Created system user: $username"
            log_audit "User created: $username (home: $home_dir)"
            return 0
        else
            log_error "Failed to create user: $username"
            log_error "Check log file for details: $LOG_FILE"
            return 1
        fi
    fi
}

# Set secure file permissions for NetBox
set_secure_permissions() {
    local install_path="$1"
    local netbox_user="${2:-netbox}"
    local netbox_group="${3:-netbox}"
    local context_label="${4:-}"  # Optional: context label (e.g., "NetBox Installation", "Security Hardening")

    log_function_entry

    # Display section header with context if provided
    if [[ -n "$context_label" ]]; then
        log_section "Setting File Permissions ($context_label)"
    else
        log_section "Setting File Permissions"
    fi

    # Create user if doesn't exist
    if ! id -u "$netbox_user" &>/dev/null; then
        create_netbox_user "$netbox_user" "$install_path" || return 1
    fi

    # Set base ownership
    log_info "Setting ownership: ${netbox_user}:${netbox_group}"
    if ! chown -R "${netbox_user}:${netbox_group}" "$install_path"; then
        log_error "Failed to set ownership"
        return 1
    fi

    # Set directory permissions (755 - readable and executable)
    log_info "Setting directory permissions (755)..."
    local dir_count=0
    while IFS= read -r dir; do
        chmod 755 "$dir" 2>/dev/null
        ((dir_count++))
        # Log progress every 100 directories
        if (( dir_count % 100 == 0 )); then
            log_info "  Processed $dir_count directories..."
        fi
    done < <(find "$install_path" -type d 2>/dev/null)
    log_info "  Total directories processed: $dir_count"

    # Set file permissions (644 - readable)
    log_info "Setting file permissions (644)..."
    local file_count=0
    while IFS= read -r file; do
        chmod 644 "$file" 2>/dev/null
        ((file_count++))
        # Log progress every 1000 files
        if (( file_count % 1000 == 0 )); then
            log_info "  Processed $file_count files..."
        fi
    done < <(find "$install_path" -type f 2>/dev/null)
    log_info "  Total files processed: $file_count"

    # Make scripts executable
    log_info "Setting executable permissions for scripts..."
    if [[ -f "${install_path}/upgrade.sh" ]]; then
        chmod 755 "${install_path}/upgrade.sh"
    fi

    # Set permissions on Python virtual environment binaries (may take a moment)
    if [[ -d "${install_path}/venv/bin" ]]; then
        log_info "Setting permissions on Python virtual environment binaries..."
        chmod 755 "${install_path}/venv/bin"/*
        log_info "Virtual environment permissions updated"
    fi

    # Protect configuration file (640 - sensitive data)
    local config_file="${install_path}/netbox/netbox/configuration.py"
    if [[ -f "$config_file" ]]; then
        log_info "Protecting configuration file (640)..."
        chmod 640 "$config_file"
        log_security "Configuration file permissions: 640"
    fi

    # Media directory (750 - writable by netbox)
    local media_dir="${install_path}/netbox/media"
    if [[ -d "$media_dir" ]]; then
        log_info "Setting media directory permissions (750)..."
        chmod 750 "$media_dir"
        log_security "Media directory permissions: 750"
    fi

    # Reports directory (750 - writable)
    local reports_dir="${install_path}/netbox/reports"
    if [[ -d "$reports_dir" ]]; then
        chmod 750 "$reports_dir"
    fi

    # Scripts directory (750 - writable)
    local scripts_dir="${install_path}/netbox/scripts"
    if [[ -d "$scripts_dir" ]]; then
        chmod 750 "$scripts_dir"
    fi

    log_success_summary "File Permissions Configuration"
    log_function_exit 0
    return 0
}

# =============================================================================
# NGINX USER CONFIGURATION
# =============================================================================

# Configure Nginx to access NetBox files
configure_nginx_access() {
    local install_path="$1"
    local netbox_user="${2:-netbox}"

    log_subsection "Configuring Nginx File Access"

    # Check if nginx user exists
    if ! id -u nginx &>/dev/null; then
        log_warn "nginx user not found, skipping nginx-specific configuration"
        return 0
    fi

    # Add nginx user to netbox group
    log_info "Adding nginx user to netbox group..."
    if usermod -a -G "$netbox_user" nginx; then
        log_security "Added nginx to ${netbox_user} group"
    else
        log_warn "Failed to add nginx to netbox group"
    fi

    # Ensure static and media directories are accessible
    local static_dir="${install_path}/netbox/static"
    local media_dir="${install_path}/netbox/media"

    if [[ -d "$static_dir" ]]; then
        chmod 755 "$static_dir"
        log_debug "Static directory accessible to nginx"
    fi

    if [[ -d "$media_dir" ]]; then
        chmod 755 "$media_dir"
        log_debug "Media directory accessible to nginx"
    fi

    return 0
}

# =============================================================================
# SECURITY HARDENING ORCHESTRATION
# =============================================================================

# Apply all security hardening (SELinux + FAPolicyD + permissions)
apply_security_hardening() {
    local install_path="$1"
    local netbox_user="${2:-netbox}"
    local netbox_group="${3:-netbox}"

    log_function_entry
    log_section "Applying Security Hardening"

    local hardening_errors=0

    # Set secure file permissions
    if ! set_secure_permissions "$install_path" "$netbox_user" "$netbox_group" "Security Hardening"; then
        log_error "Failed to set secure permissions"
        ((hardening_errors++))
    fi

    # Configure Nginx access
    configure_nginx_access "$install_path" "$netbox_user"

    # Configure SELinux
    if ! configure_selinux "$install_path"; then
        log_warn "SELinux configuration completed with warnings"
    fi

    # Configure FAPolicyD
    if ! configure_fapolicyd "$install_path"; then
        log_warn "FAPolicyD configuration completed with warnings"
    fi

    # Audit security configuration
    audit_security_configuration "$install_path"

    if [[ $hardening_errors -gt 0 ]]; then
        log_error "Security hardening completed with $hardening_errors error(s)"
        log_function_exit 1
        return 1
    fi

    log_success_summary "Security Hardening Complete"
    log_function_exit 0
    return 0
}

# =============================================================================
# SECURITY AUDIT
# =============================================================================

# Audit security configuration
audit_security_configuration() {
    local install_path="$1"

    log_section "Security Configuration Audit"

    local issues_found=0

    # Check SELinux status
    if is_selinux_installed; then
        local selinux_mode
        selinux_mode=$(get_selinux_mode)
        log_info "SELinux mode: $selinux_mode"

        if [[ "$selinux_mode" != "Enforcing" ]]; then
            log_warn "SELinux not in Enforcing mode"
            ((issues_found++))
        fi
    else
        log_warn "SELinux not installed"
        ((issues_found++))
    fi

    # Check FAPolicyD status
    if is_fapolicyd_active; then
        log_info "FAPolicyD is active"
    else
        log_warn "FAPolicyD not active"
    fi

    # Check file permissions on configuration
    local config_file="${install_path}/netbox/netbox/configuration.py"
    if [[ -f "$config_file" ]]; then
        local perms
        perms=$(stat -c %a "$config_file" 2>/dev/null || stat -f %OLp "$config_file" 2>/dev/null)

        if [[ "$perms" == "640" ]]; then
            log_info "Configuration file permissions: $perms (secure)"
        else
            log_warn "Configuration file permissions: $perms (should be 640)"
            ((issues_found++))
        fi
    fi

    if [[ $issues_found -gt 0 ]]; then
        log_warn "Security audit found $issues_found potential issue(s)"
        log_warn "Review and address security warnings for production use"
    else
        log_info "Security audit passed"
    fi

    return 0
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize security module
init_security() {
    log_debug "Security module initialized"
}

# Auto-initialize when sourced
init_security

# End of security.sh
