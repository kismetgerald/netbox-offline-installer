#!/bin/bash
#
# NetBox Offline Installer - VM Snapshot Management
# Version: 0.0.1
# Description: VMware and XCP-ng snapshot creation and management
#
# Created by: Kismet Agbasi (KismetG17@gmail.com)
# AI Collaborator: Claude Code (integrated with VS Code)
# Date Created: 12/27/2025
# Last Updated: 01/11/2026
#

# =============================================================================
# VM PLATFORM DETECTION
# =============================================================================

# Detect VM platform
detect_vm_platform() {
    log_function_entry

    # Check for VMware Tools
    if command -v vmware-toolbox-cmd &>/dev/null; then
        echo "vmware"
        log_debug "Detected VMware platform"
        return 0
    fi

    # Check for XCP-ng/Xen hypervisor
    # Note: XCP-ng VMs don't have xe-cli, so check for Xen hypervisor presence
    if [[ -d /proc/xen ]] || \
       grep -qi "xen" /sys/hypervisor/type 2>/dev/null || \
       systemd-detect-virt 2>/dev/null | grep -qi "xen"; then
        echo "xcp-ng"
        log_debug "Detected XCP-ng/Xen platform"
        return 0
    fi

    # Check for QEMU guest agent
    if command -v qemu-ga &>/dev/null || \
       systemctl is-active --quiet qemu-guest-agent 2>/dev/null; then
        echo "qemu"
        log_debug "Detected QEMU/KVM platform"
        return 0
    fi

    # Check for VirtualBox guest additions
    if command -v VBoxControl &>/dev/null; then
        echo "virtualbox"
        log_debug "Detected VirtualBox platform"
        return 0
    fi

    # Check via systemd-detect-virt
    if command -v systemd-detect-virt &>/dev/null; then
        local virt_type
        virt_type=$(systemd-detect-virt 2>/dev/null)

        case "$virt_type" in
            vmware)
                echo "vmware"
                log_debug "Detected VMware via systemd-detect-virt"
                return 0
                ;;
            kvm|qemu)
                echo "qemu"
                log_debug "Detected QEMU/KVM via systemd-detect-virt"
                return 0
                ;;
            xen)
                echo "xen"
                log_debug "Detected Xen via systemd-detect-virt"
                return 0
                ;;
        esac
    fi

    # No virtualization detected
    echo "none"
    log_debug "No VM platform detected (physical machine or unsupported hypervisor)"
    log_function_exit 1
    return 1
}

# Check if VM platform is supported for snapshots
is_snapshot_supported() {
    local platform="$1"

    case "$platform" in
        vmware|xcp-ng)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# =============================================================================
# VMWARE SNAPSHOT FUNCTIONS
# =============================================================================

# Check VMware Tools status
check_vmware_tools() {
    if ! command -v vmware-toolbox-cmd &>/dev/null; then
        log_warn "VMware Tools not found"
        return 1
    fi

    # Check if VMware Tools are running
    if ! vmware-toolbox-cmd -v &>/dev/null; then
        log_warn "VMware Tools not running properly"
        return 1
    fi

    local version
    version=$(vmware-toolbox-cmd -v 2>/dev/null)
    log_info "VMware Tools version: $version"

    return 0
}

# Create VMware snapshot
create_vmware_snapshot() {
    local snapshot_name="$1"

    log_subsection "VMware Snapshot"

    # Check VMware Tools
    if ! check_vmware_tools; then
        log_warn "VMware Tools not available for snapshot creation"
        return 1
    fi

    # Note: VMware snapshots are typically created from the hypervisor
    # VMware Tools running in the guest cannot directly create snapshots
    # This function provides information and pauses for manual snapshot

    log_warn "VMware snapshots must be created from vSphere/ESXi console"
    log_info "Please create a snapshot with the following details:"
    log_info "  Snapshot Name: $snapshot_name"
    log_info "  Description: NetBox offline installer pre-installation snapshot"
    log_info "  Memory: Include (recommended)"
    log_info "  Quiesce: Yes (if VMware Tools supports it)"

    echo
    cat <<EOF
================================================================================
MANUAL ACTION REQUIRED: VMware Snapshot
================================================================================
Please create a snapshot in vSphere/ESXi with these settings:

  Name:        $snapshot_name
  Description: NetBox offline installer - $(date '+%Y-%m-%d %H:%M:%S')
  Memory:      Include (recommended for full state)
  Quiesce:     Yes (ensures filesystem consistency)

================================================================================
EOF

    # Wait for user confirmation (with timeout)
    local wait_time=60
    log_info "Waiting up to ${wait_time} seconds for snapshot creation..."

    read -t "$wait_time" -r -p "Press Enter when snapshot is complete (or wait $wait_time seconds to continue): " || {
        log_warn "Timeout waiting for snapshot confirmation"
        log_warn "Proceeding without snapshot verification"
    }

    echo
    log_info "Continuing with installation..."

    return 0
}

# =============================================================================
# XCP-NG SNAPSHOT FUNCTIONS (via Xen Orchestra REST API)
# =============================================================================

# Get VM UUID for XCP-ng
get_xcpng_vm_uuid() {
    local uuid

    # Method 1: Check /sys/hypervisor/uuid (most reliable for Xen guests)
    if [[ -f /sys/hypervisor/uuid ]]; then
        uuid=$(cat /sys/hypervisor/uuid 2>/dev/null | tr -d '[:space:]')
        if [[ -n "$uuid" && "$uuid" != "00000000-0000-0000-0000-000000000000" ]]; then
            echo "$uuid"
            return 0
        fi
    fi

    # Method 2: Use dmidecode to get system UUID
    if command -v dmidecode &>/dev/null; then
        uuid=$(dmidecode -s system-uuid 2>/dev/null | tr -d '[:space:]')
        if [[ -n "$uuid" && "$uuid" != "00000000-0000-0000-0000-000000000000" ]]; then
            echo "$uuid"
            return 0
        fi
    fi

    # Method 3: Check xenstore (if xenstore-read is available)
    if command -v xenstore-read &>/dev/null; then
        uuid=$(xenstore-read vm 2>/dev/null | sed 's|/vm/||')
        if [[ -n "$uuid" ]]; then
            echo "$uuid"
            return 0
        fi
    fi

    log_error "Could not determine VM UUID"
    return 1
}

# Validate Xen Orchestra configuration
validate_xen_orchestra_config() {
    log_function_entry

    # Check for required configuration
    if [[ -z "${XO_API_URL}" ]]; then
        log_error "XO_API_URL not configured (required for XCP-ng snapshots via Xen Orchestra)"
        log_error "Set XO_API_URL in configuration (e.g., https://xo.example.com)"
        log_function_exit 1
        return 1
    fi

    if [[ -z "${XO_API_TOKEN}" ]]; then
        log_error "XO_API_TOKEN not configured (required for XCP-ng snapshots via Xen Orchestra)"
        log_error "Set XO_API_TOKEN in configuration (obtain from Xen Orchestra admin user)"
        log_function_exit 1
        return 1
    fi

    # Validate URL format
    if [[ ! "$XO_API_URL" =~ ^https?:// ]]; then
        log_error "XO_API_URL must start with http:// or https://"
        log_function_exit 1
        return 1
    fi

    log_debug "Xen Orchestra configuration validated"
    log_function_exit 0
    return 0
}

# Get curl SSL options based on configuration
get_curl_ssl_options() {
    local curl_opts=""

    # Check if SSL verification should be disabled
    if [[ "${XO_API_INSECURE_SSL,,}" == "yes" || "${XO_API_INSECURE_SSL,,}" == "true" ]]; then
        curl_opts="--insecure"
        log_debug "SSL certificate verification disabled for Xen Orchestra API"
    else
        # Check if custom CA bundle is provided
        if [[ -n "${XO_API_CA_BUNDLE}" && -f "${XO_API_CA_BUNDLE}" ]]; then
            curl_opts="--cacert ${XO_API_CA_BUNDLE}"
            log_debug "Using custom CA bundle: ${XO_API_CA_BUNDLE}"
        else
            # Use system CA bundle (default behavior)
            log_debug "Using system CA bundle for SSL verification"
        fi
    fi

    echo "$curl_opts"
}

# Test Xen Orchestra API connectivity
test_xen_orchestra_connection() {
    local xo_url="$1"
    local xo_token="$2"

    log_debug "Testing Xen Orchestra API connectivity"

    # Remove trailing slash from URL
    xo_url="${xo_url%/}"

    # Get SSL options
    local curl_ssl_opts
    curl_ssl_opts=$(get_curl_ssl_options)

    # Test basic connectivity with a simple API call
    local response
    local http_code

    response=$(curl -s -w "\n%{http_code}" \
        ${curl_ssl_opts} \
        -b "authenticationToken=${xo_token}" \
        -H "Content-Type: application/json" \
        "${xo_url}/rest/v0/vms" \
        2>/dev/null)

    http_code=$(echo "$response" | tail -1)

    if [[ "$http_code" == "200" ]]; then
        log_debug "Xen Orchestra API connection successful"
        return 0
    elif [[ "$http_code" == "401" ]]; then
        log_error "Xen Orchestra API authentication failed (401 Unauthorized)"
        log_error "Check XO_API_TOKEN value"
        return 1
    else
        log_warn "Xen Orchestra API returned HTTP $http_code"
        log_warn "Connection may have issues, but attempting snapshot anyway"
        return 0
    fi
}

# Create XCP-ng snapshot via Xen Orchestra REST API
create_xcpng_snapshot() {
    local snapshot_name="$1"

    log_subsection "XCP-ng Snapshot (via Xen Orchestra)"

    # Validate Xen Orchestra configuration
    if ! validate_xen_orchestra_config; then
        log_warn "XCP-ng snapshot requires Xen Orchestra REST API configuration"
        log_warn "Please configure XO_API_URL and XO_API_TOKEN in install.conf"
        log_warn ""
        log_warn "Example configuration:"
        log_warn "  XO_API_URL=\"https://xo.example.com\""
        log_warn "  XO_API_TOKEN=\"your-authentication-token-here\""
        log_warn ""
        log_warn "To create a manual snapshot:"
        log_warn "  1. Log into Xen Orchestra web interface"
        log_warn "  2. Navigate to this VM"
        log_warn "  3. Click 'Snapshots' tab"
        log_warn "  4. Create snapshot named: $snapshot_name"
        return 1
    fi

    # Get VM UUID
    local vm_uuid
    vm_uuid=$(get_xcpng_vm_uuid)

    if [[ -z "$vm_uuid" ]]; then
        log_error "Cannot create snapshot: VM UUID not found"
        return 1
    fi

    log_info "VM UUID: $vm_uuid"
    log_info "Xen Orchestra URL: $XO_API_URL"

    # Test API connectivity
    if ! test_xen_orchestra_connection "$XO_API_URL" "$XO_API_TOKEN"; then
        log_warn "Xen Orchestra API connection test failed"
        log_warn "Attempting snapshot creation anyway..."
    fi

    # Remove trailing slash from URL
    local xo_url="${XO_API_URL%/}"

    # Prepare snapshot API endpoint
    local api_endpoint="${xo_url}/rest/v0/vms/${vm_uuid}/actions/snapshot"

    log_info "Creating snapshot: $snapshot_name"
    log_debug "API endpoint: $api_endpoint"

    # Get SSL options
    local curl_ssl_opts
    curl_ssl_opts=$(get_curl_ssl_options)

    # Create snapshot via REST API
    local response
    local http_code

    response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        ${curl_ssl_opts} \
        -b "authenticationToken=${XO_API_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"name_label\": \"${snapshot_name}\"}" \
        "$api_endpoint" \
        2>/dev/null)

    http_code=$(echo "$response" | tail -1)
    local response_body
    response_body=$(echo "$response" | sed '$d')

    # Check response
    if [[ "$http_code" == "200" || "$http_code" == "201" || "$http_code" == "202" ]]; then
        log_info "Snapshot created successfully"
        log_security "XCP-ng snapshot created via Xen Orchestra API: $snapshot_name"
        log_debug "API response: $response_body"
        return 0
    elif [[ "$http_code" == "401" ]]; then
        log_error "Snapshot creation failed: Authentication error (401 Unauthorized)"
        log_error "Check XO_API_TOKEN value"
        log_error "Token must be from an admin user account"
        return 1
    elif [[ "$http_code" == "404" ]]; then
        log_error "Snapshot creation failed: VM not found (404 Not Found)"
        log_error "VM UUID may be incorrect: $vm_uuid"
        log_error "Verify VM UUID in Xen Orchestra web interface"
        return 1
    else
        log_warn "Snapshot creation returned HTTP $http_code"
        log_warn "Response: $response_body"
        log_warn "You can create the snapshot manually from Xen Orchestra:"
        log_warn "  VM UUID: $vm_uuid"
        log_warn "  Snapshot Name: $snapshot_name"
        return 1
    fi
}

# =============================================================================
# GENERIC SNAPSHOT FUNCTIONS
# =============================================================================

# Create VM snapshot (platform-agnostic)
create_vm_snapshot() {
    local snapshot_name="${1:-netbox-pre-install}"

    log_function_entry

    # Check if snapshots are enabled
    if [[ "${VM_SNAPSHOT_ENABLED,,}" != "yes" ]]; then
        log_info "VM snapshots disabled in configuration"
        log_function_exit 0
        return 0
    fi

    log_section "VM Snapshot Creation"

    # Add timestamp to snapshot name
    local timestamp
    timestamp=$(date '+%Y%m%d-%H%M%S')
    local full_snapshot_name="${snapshot_name}-${timestamp}"

    # Detect VM platform
    local platform
    platform=$(detect_vm_platform)

    log_info "Detected platform: $platform"
    log_info "Snapshot name: $full_snapshot_name"

    # Create snapshot based on platform
    local snapshot_result=0

    case "$platform" in
        vmware)
            create_vmware_snapshot "$full_snapshot_name"
            snapshot_result=$?
            ;;

        xcp-ng)
            create_xcpng_snapshot "$full_snapshot_name"
            snapshot_result=$?
            ;;

        qemu)
            log_warn "QEMU/KVM detected"
            log_warn "Snapshots must be created from the hypervisor (virsh, virt-manager)"
            log_info "Recommended virsh command:"
            log_info "  virsh snapshot-create-as <domain> $full_snapshot_name"
            snapshot_result=1
            ;;

        virtualbox)
            log_warn "VirtualBox detected"
            log_warn "Snapshots must be created from VirtualBox Manager"
            snapshot_result=1
            ;;

        xen)
            log_warn "Xen detected"
            log_warn "Snapshots must be created from Xen management tools"
            snapshot_result=1
            ;;

        none)
            log_info "No virtualization detected (physical machine)"
            log_info "Skipping VM snapshot creation"
            snapshot_result=0
            ;;

        *)
            log_warn "Unknown or unsupported virtualization platform: $platform"
            snapshot_result=1
            ;;
    esac

    # Handle snapshot result
    if [[ $snapshot_result -eq 0 ]]; then
        log_info "VM snapshot process completed successfully"
        log_function_exit 0
        return 0
    else
        log_warn "VM snapshot creation failed or requires manual intervention"
        log_warn "Continuing with installation (as configured)"
        log_info "IMPORTANT: It is strongly recommended to create a snapshot"
        log_info "before proceeding with the installation for rollback capability"

        # Ask user if they want to continue
        echo
        if ! confirm_action "Continue without VM snapshot?" "n"; then
            log_info "Installation cancelled by user"
            exit 0
        fi

        log_function_exit 1
        return 1
    fi
}

# Create VM snapshot with safe error handling
create_vm_snapshot_safe() {
    local snapshot_name="${1:-netbox-pre-install}"

    # Fix #52: Check if snapshots are enabled before attempting creation
    if [[ "${VM_SNAPSHOT_ENABLED,,}" != "yes" ]]; then
        # Snapshots disabled - don't print success message
        return 0
    fi

    # Attempt to create snapshot
    if create_vm_snapshot "$snapshot_name"; then
        log_info "VM snapshot created successfully"
        return 0
    else
        log_warn "VM snapshot failed, but continuing installation"
        log_warn "RECOMMENDATION: Create a manual snapshot before proceeding"

        # Small delay to allow user to read the warning
        sleep 2

        return 0  # Return success to allow installation to continue
    fi
}

# =============================================================================
# SNAPSHOT VERIFICATION
# =============================================================================

# List available snapshots (if possible)
list_vm_snapshots() {
    local platform
    platform=$(detect_vm_platform)

    log_subsection "Available VM Snapshots"

    case "$platform" in
        vmware)
            log_info "VMware snapshots can be viewed in vSphere/ESXi console"
            log_info "Use vSphere Client to manage snapshots"
            ;;

        xcp-ng)
            if command -v xe &>/dev/null; then
                local vm_uuid
                vm_uuid=$(get_xcpng_vm_uuid 2>/dev/null)

                if [[ -n "$vm_uuid" ]]; then
                    log_info "XCP-ng snapshots for this VM:"
                    xe snapshot-list vm-uuid="$vm_uuid" 2>/dev/null || \
                        log_warn "Could not list snapshots"
                fi
            else
                log_info "Use XCP-ng Center to view snapshots"
            fi
            ;;

        *)
            log_info "Snapshot listing not available for platform: $platform"
            ;;
    esac
}

# =============================================================================
# SNAPSHOT RECOMMENDATIONS
# =============================================================================

# Display snapshot recommendations
display_snapshot_recommendations() {
    local platform="$1"

    cat <<EOF

================================================================================
VM Snapshot Recommendations
================================================================================

Platform: $platform

Best Practices:
  1. Always create a snapshot before major changes
  2. Include memory state for full rollback capability
  3. Use filesystem quiescing if supported (VMware Tools)
  4. Document snapshot purpose in description
  5. Test snapshot restore procedure before relying on it

For Production Systems:
  - Create snapshot during maintenance window
  - Verify snapshot creation succeeded
  - Test restoration before proceeding
  - Keep snapshots for limited time (performance impact)
  - Clean up old snapshots after verification

================================================================================

EOF
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize VM snapshot module
init_vm_snapshot() {
    log_debug "VM snapshot module initialized"

    # Detect platform on load
    local platform
    platform=$(detect_vm_platform)

    if [[ "$platform" != "none" ]]; then
        log_debug "VM platform available: $platform"
    fi
}

# Auto-initialize when sourced
init_vm_snapshot

# End of vm-snapshot.sh
