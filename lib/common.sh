#!/bin/bash
#
# NetBox Offline Installer - Common Utilities
# Version: 0.0.1
# Description: Common functions, constants, and validation utilities
#
# Created by: Kismet Agbasi (KismetG17@gmail.com)
# AI Collaborator: Claude Code (integrated with VS Code)
# Date Created: 12/27/2025
# Last Updated: 01/11/2026
#

# =============================================================================
# CONSTANTS
# =============================================================================

# Fix #33: INSTALLER_VERSION moved to config/defaults.conf
# This ensures it's defined before logging module loads

# Supported RHEL versions
readonly SUPPORTED_RHEL_VERSIONS=("8" "9" "10")

# NetBox requirements
readonly MIN_PYTHON_VERSION="3.10"
readonly MIN_POSTGRESQL_VERSION="14"
readonly MIN_REDIS_VERSION="4.0"

# System requirements
readonly MIN_DISK_SPACE_GB=5
readonly MIN_RAM_GB=4

# =============================================================================
# USER AND PERMISSION CHECKS
# =============================================================================

# Check if running as root
check_root_user() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        log_error "Please run with sudo or as root user"
        exit 1
    fi
}

# =============================================================================
# OPERATING SYSTEM DETECTION
# =============================================================================

# Check if running on supported OS
check_supported_os() {
    if [[ ! -f /etc/redhat-release ]]; then
        log_error "This installer only supports RHEL-based distributions"
        log_error "Detected OS is not RHEL/Rocky/AlmaLinux"
        exit 1
    fi

    local rhel_version
    rhel_version=$(get_rhel_version)

    if [[ ! " ${SUPPORTED_RHEL_VERSIONS[*]} " =~ " ${rhel_version} " ]]; then
        log_error "Unsupported RHEL version: $rhel_version"
        log_error "Supported versions: ${SUPPORTED_RHEL_VERSIONS[*]}"
        exit 1
    fi

    log_info "Detected RHEL version: $rhel_version"
    echo "$rhel_version"
}

# Get RHEL major version
get_rhel_version() {
    local version

    # Method 1: Parse /etc/redhat-release (most reliable)
    if [[ -f /etc/redhat-release ]]; then
        version=$(sed 's/.*release \([0-9]\+\).*/\1/' /etc/redhat-release 2>/dev/null)
    fi

    # Method 2: Try os-release
    if [[ -z "$version" ]] && [[ -f /etc/os-release ]]; then
        version=$(grep -oP 'VERSION_ID="\K[0-9]+' /etc/os-release 2>/dev/null | head -1)
    fi

    # Method 3: Try rpm query (only if above methods failed)
    if [[ -z "$version" ]] && command -v rpm &>/dev/null; then
        version=$(rpm -q --queryformat '%{VERSION}' redhat-release-server 2>/dev/null || \
                  rpm -q --queryformat '%{VERSION}' rocky-release 2>/dev/null || \
                  rpm -q --queryformat '%{VERSION}' almalinux-release 2>/dev/null || \
                  rpm -q --queryformat '%{VERSION}' centos-stream-release 2>/dev/null)
        # Clean up "package X is not installed" messages
        version=$(echo "$version" | grep -oP '^\d+$' || echo "")
    fi

    if [[ -z "$version" ]]; then
        log_error "Could not detect RHEL version"
        log_error "Please ensure /etc/redhat-release or /etc/os-release exists"
        exit 1
    fi

    echo "$version"
}

# Get RHEL full version (major.minor)
# Returns: Version string like "8.10", "9.4", "10.0"
get_rhel_full_version() {
    local full_version

    # Method 1: Parse /etc/redhat-release
    if [[ -f /etc/redhat-release ]]; then
        full_version=$(grep -oP 'release \K[0-9]+\.[0-9]+' /etc/redhat-release 2>/dev/null | head -1)
    fi

    # Method 2: Try os-release
    if [[ -z "$full_version" ]] && [[ -f /etc/os-release ]]; then
        full_version=$(grep -oP 'VERSION_ID="\K[0-9]+\.[0-9]+' /etc/os-release 2>/dev/null | head -1)
    fi

    if [[ -z "$full_version" ]]; then
        log_error "Could not detect RHEL full version"
        log_error "Please ensure /etc/redhat-release or /etc/os-release exists"
        return 1
    fi

    echo "$full_version"
    return 0
}

# Detect RHEL version with detailed info
# Returns: Major version and sets global variables for minor version
detect_rhel_version() {
    local major_version
    major_version=$(get_rhel_version)

    if [[ $? -ne 0 ]]; then
        log_error "Failed to detect RHEL version"
        return 1
    fi

    local full_version
    full_version=$(get_rhel_full_version)

    if [[ $? -ne 0 ]]; then
        log_error "Failed to detect RHEL full version"
        return 1
    fi

    log_info "Detected RHEL $full_version"
    echo "$major_version"
    return 0
}

# Validate package OS version matches target system
# Usage: validate_package_os_match <package_dir> <target_rhel_version>
# Returns: 0 if match, 1 if mismatch
validate_package_os_match() {
    local package_dir="$1"
    local target_version="$2"
    local manifest="$package_dir/manifest.txt"

    if [[ ! -f "$manifest" ]]; then
        log_error "Manifest file not found: $manifest"
        log_error "Cannot validate package OS version"
        return 1
    fi

    local package_os
    package_os=$(grep -oP 'RHEL Version:\s+\K[0-9]+' "$manifest" 2>/dev/null)

    if [[ -z "$package_os" ]]; then
        log_error "Could not determine package OS version from manifest"
        log_error "Manifest may be corrupted or from older installer version"
        return 1
    fi

    if [[ "$package_os" != "$target_version" ]]; then
        log_error "Package OS version mismatch!"
        log_error "  Package built for:  RHEL $package_os"
        log_error "  Target system:      RHEL $target_version"
        log_error ""
        log_error "This package cannot be used on this system."
        log_error "Please build a new package on a RHEL $target_version system."
        return 1
    fi

    log_info "Package OS version validated: RHEL $package_os"
    return 0
}

# =============================================================================
# SYSTEM RESOURCE CHECKS
# =============================================================================

# Check available disk space
check_disk_space() {
    local path="$1"
    local required_gb="$2"

    # Get available space in KB
    local available_kb
    available_kb=$(df -k "$path" 2>/dev/null | awk 'NR==2 {print $4}')

    if [[ -z "$available_kb" ]]; then
        log_error "Could not determine disk space for $path"
        return 1
    fi

    # Convert to GB
    local available_gb=$((available_kb / 1024 / 1024))

    if [[ $available_gb -lt $required_gb ]]; then
        log_error "Insufficient disk space on $path"
        log_error "Required: ${required_gb}GB, Available: ${available_gb}GB"
        return 1
    fi

    log_info "Disk space check passed: ${available_gb}GB available on $path"
    return 0
}

# Check available RAM
check_available_ram() {
    local required_gb="${1:-$MIN_RAM_GB}"

    # Get total RAM in KB
    local total_ram_kb
    total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')

    # Convert to GB
    local total_ram_gb=$((total_ram_kb / 1024 / 1024))

    if [[ $total_ram_gb -lt $required_gb ]]; then
        log_warn "Low RAM detected: ${total_ram_gb}GB available, ${required_gb}GB recommended"
        log_warn "Installation may be slow or fail"
        return 1
    fi

    log_info "RAM check passed: ${total_ram_gb}GB available"
    return 0
}

# =============================================================================
# NETWORK CHECKS
# =============================================================================

# Check internet connectivity
verify_internet_connectivity() {
    log_info "Checking internet connectivity..."

    # Try to ping Google's DNS
    if ping -c 1 -W 5 8.8.8.8 &>/dev/null; then
        log_info "Internet connectivity verified"
        return 0
    fi

    # Try alternative DNS
    if ping -c 1 -W 5 1.1.1.1 &>/dev/null; then
        log_info "Internet connectivity verified (via 1.1.1.1)"
        return 0
    fi

    log_error "No internet connectivity detected"
    log_error "This mode requires internet access"
    return 1
}

# =============================================================================
# VERSION COMPARISON
# =============================================================================

# Compare two version strings
# Usage: version_compare "1.2.3" ">=" "1.2.0"
# Returns: 0 if comparison is true, 1 if false
version_compare() {
    local version1="$1"
    local operator="$2"
    local version2="$3"

    # Use sort -V for version comparison
    local result
    result=$(printf '%s\n%s\n' "$version1" "$version2" | sort -V | head -n1)

    case "$operator" in
        "==")
            [[ "$version1" == "$version2" ]]
            ;;
        "!=")
            [[ "$version1" != "$version2" ]]
            ;;
        "<")
            [[ "$result" == "$version1" && "$version1" != "$version2" ]]
            ;;
        "<=")
            [[ "$result" == "$version1" ]]
            ;;
        ">")
            [[ "$result" == "$version2" && "$version1" != "$version2" ]]
            ;;
        ">=")
            [[ "$result" == "$version2" ]]
            ;;
        *)
            log_error "Invalid comparison operator: $operator"
            log_error "Valid operators: ==, !=, <, <=, >, >="
            return 2
            ;;
    esac
}

# =============================================================================
# FILE AND PATH UTILITIES
# =============================================================================

# Check if a command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# Get absolute path
get_absolute_path() {
    local path="$1"

    if [[ -d "$path" ]]; then
        (cd "$path" && pwd)
    elif [[ -f "$path" ]]; then
        local dir
        dir=$(dirname "$path")
        local file
        file=$(basename "$path")
        (cd "$dir" && echo "$(pwd)/$file")
    else
        # Path doesn't exist, return as-is if absolute, or make absolute
        if [[ "$path" = /* ]]; then
            echo "$path"
        else
            echo "$(pwd)/$path"
        fi
    fi
}

# Create directory with proper permissions
create_directory() {
    local dir="$1"
    local owner="${2:-root}"
    local group="${3:-root}"
    local perms="${4:-755}"

    if [[ ! -d "$dir" ]]; then
        log_info "Creating directory: $dir"
        mkdir -p "$dir" || {
            log_error "Failed to create directory: $dir"
            return 1
        }
    fi

    chown "${owner}:${group}" "$dir"
    chmod "$perms" "$dir"

    return 0
}

# =============================================================================
# USER INTERACTION
# =============================================================================

# Confirm action with user
confirm_action() {
    local message="$1"
    local default="${2:-n}"

    local prompt
    if [[ "$default" == "y" ]]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi

    local response
    read -r -p "$message $prompt: " response
    response="${response:-$default}"

    [[ "${response,,}" == "y" || "${response,,}" == "yes" ]]
}

# Display progress spinner
show_spinner() {
    local pid=$1
    local message="$2"
    local spinstr='|/-\'
    local i=0

    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % 4 ))
        printf "\r%s ${spinstr:$i:1}" "$message"
        sleep 0.1
    done

    printf "\r%s Done\n" "$message"
}

# =============================================================================
# INSTALLER INFORMATION
# =============================================================================

# Get installer version
get_installer_version() {
    echo "$INSTALLER_VERSION"
}

# Display installer header
display_header() {
    # Log header to file only (not to console)
    {
        echo "===================================="
        echo "   NetBox Offline Installer"
        echo "===================================="
        echo "Version: $INSTALLER_VERSION"
        echo "RHEL Version: $(get_rhel_version)"
        echo "===================================="
        echo
    } >> "$LOG_FILE"
}

# =============================================================================
# CLEANUP AND SIGNAL HANDLING
# =============================================================================

# Cleanup temporary files on exit
cleanup_on_exit() {
    log_debug "Performing cleanup..."

    # Remove temporary files
    if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
        log_debug "Removing temporary directory: $TEMP_DIR"
        rm -rf "$TEMP_DIR"
    fi

    # Clear sensitive variables
    unset DB_PASSWORD DB_ADMIN_PASSWORD SUPERUSER_PASSWORD SECRET_KEY

    log_debug "Cleanup completed"
}

# Set up signal handlers for cleanup
setup_signal_handlers() {
    trap cleanup_on_exit EXIT
    trap 'log_error "Script interrupted by user"; exit 130' INT
    trap 'log_error "Script terminated"; exit 143' TERM
}

# =============================================================================
# PACKAGE VERIFICATION
# =============================================================================

# Verify package integrity using checksums
verify_package_integrity() {
    local package_dir="$1"
    local checksum_file="${package_dir}/checksums.txt"

    if [[ ! -f "$checksum_file" ]]; then
        log_error "Checksum file not found: $checksum_file"
        return 1
    fi

    log_info "Verifying package integrity..."

    if ! (cd "$package_dir" && sha256sum -c checksums.txt --quiet); then
        log_error "Package integrity verification failed"
        log_error "Checksums do not match - package may be corrupted"
        return 1
    fi

    log_info "Package integrity verified successfully"
    return 0
}

# =============================================================================
# REPOSITORY MANAGEMENT
# =============================================================================

# Setup local repository from RHEL ISO
setup_local_repo_from_iso() {
    local iso_path="$1"
    local mount_point="/mnt/rhel-iso"
    local repo_file="/etc/yum.repos.d/local-rhel.repo"

    log_function_entry

    # Check if ISO path provided
    if [[ -z "$iso_path" ]]; then
        log_info "No ISO path provided"
        log_info "To setup local repository, provide ISO path:"
        log_info "  setup_local_repo_from_iso /path/to/rhel.iso"
        log_function_exit 1
        return 1
    fi

    # Verify ISO exists
    if [[ ! -f "$iso_path" ]]; then
        log_error "ISO file not found: $iso_path"
        log_function_exit 1
        return 1
    fi

    log_info "Setting up local repository from ISO: $iso_path"

    # Create mount point
    if [[ ! -d "$mount_point" ]]; then
        log_debug "Creating mount point: $mount_point"
        mkdir -p "$mount_point"
    fi

    # Check if already mounted
    if mount | grep -q "$mount_point"; then
        log_warn "ISO already mounted at $mount_point"
    else
        # Mount ISO
        log_info "Mounting ISO to $mount_point..."
        if ! mount -o loop,ro "$iso_path" "$mount_point"; then
            log_error "Failed to mount ISO"
            log_function_exit 1
            return 1
        fi
        log_info "ISO mounted successfully"
    fi

    # Create repository configuration
    log_info "Creating local repository configuration: $repo_file"
    cat > "$repo_file" <<EOF
# Local RHEL repository from ISO
# Created by NetBox Offline Installer
# ISO: $iso_path
# Mount: $mount_point

[local-rhel-baseos]
name=Local RHEL BaseOS
baseurl=file://$mount_point/BaseOS
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[local-rhel-appstream]
name=Local RHEL AppStream
baseurl=file://$mount_point/AppStream
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
EOF

    # Clean and update repository cache
    log_info "Updating repository cache..."
    dnf clean all &>/dev/null
    dnf makecache &>/dev/null

    # Verify repositories are accessible
    if dnf repolist 2>&1 | grep -q "local-rhel"; then
        log_info "Local repository configured successfully"
        log_info "Available repositories:"
        dnf repolist 2>&1 | grep "local-rhel" | while read -r line; do
            log_info "  $line"
        done
        log_function_exit 0
        return 0
    else
        log_error "Failed to configure local repository"
        log_error "Repository does not appear in repolist"
        log_function_exit 1
        return 1
    fi
}

# Detect mounted RHEL DVD/ISO
detect_rhel_dvd() {
    log_function_entry

    # Check common mount points for optical media
    local common_mounts=("/media/cdrom" "/media/dvd" "/mnt/cdrom" "/mnt/dvd" "/run/media/"*)
    local detected_path=""

    # First check for any already-mounted iso9660 filesystems
    log_debug "Scanning for mounted optical media..."

    # Get all mounted iso9660 or udf filesystems (DVD/CD formats)
    while IFS= read -r mount_line; do
        local mount_point
        mount_point=$(echo "$mount_line" | awk '{print $3}')

        log_debug "Checking mount point: $mount_point"

        # Verify it's a RHEL ISO by checking for characteristic files
        if [[ -f "$mount_point/.discinfo" ]] || \
           [[ -d "$mount_point/BaseOS" ]] || \
           [[ -d "$mount_point/AppStream" ]] || \
           [[ -f "$mount_point/media.repo" ]]; then

            log_debug "Found potential RHEL media at: $mount_point"

            # Try to read .discinfo or media.repo to confirm it's RHEL
            if [[ -f "$mount_point/.discinfo" ]]; then
                if grep -qi "red hat\|rhel" "$mount_point/.discinfo" 2>/dev/null; then
                    detected_path="$mount_point"
                    break
                fi
            elif [[ -f "$mount_point/media.repo" ]]; then
                if grep -qi "red hat\|rhel" "$mount_point/media.repo" 2>/dev/null; then
                    detected_path="$mount_point"
                    break
                fi
            elif [[ -d "$mount_point/BaseOS" && -d "$mount_point/AppStream" ]]; then
                # Has both BaseOS and AppStream, likely RHEL
                detected_path="$mount_point"
                break
            fi
        fi
    done < <(mount | grep -E "type (iso9660|udf)")

    if [[ -n "$detected_path" ]]; then
        log_info "Detected RHEL installation media at: $detected_path"
        echo "$detected_path"
        log_function_exit 0
        return 0
    fi

    # If no mounted DVD found, check for unmounted DVD devices (STIG systems)
    log_debug "No mounted DVD found, checking for unmounted DVD devices..."
    local dvd_devices=("/dev/sr0" "/dev/cdrom" "/dev/dvd" "/dev/sr1")

    for device in "${dvd_devices[@]}"; do
        if [[ -b "$device" ]]; then
            log_debug "Found block device: $device"

            # Try to mount it temporarily
            local temp_mount="/mnt/rhel-dvd-temp"
            mkdir -p "$temp_mount" 2>/dev/null

            if mount -o ro "$device" "$temp_mount" 2>/dev/null; then
                log_debug "Successfully mounted $device at $temp_mount"

                # Check if it's a RHEL DVD
                if [[ -f "$temp_mount/.discinfo" ]] || \
                   [[ -d "$temp_mount/BaseOS" ]] || \
                   [[ -d "$temp_mount/AppStream" ]]; then

                    log_info "Found RHEL installation DVD at $device"
                    detected_path="$temp_mount"
                    echo "$detected_path"
                    log_function_exit 0
                    return 0
                else
                    # Not a RHEL DVD, unmount it
                    log_debug "$device does not contain RHEL installation media"
                    umount "$temp_mount" 2>/dev/null
                fi
            fi
        fi
    done

    # Cleanup temp mount point if not used
    if [[ -z "$detected_path" ]]; then
        rmdir /mnt/rhel-dvd-temp 2>/dev/null
    fi

    log_debug "No RHEL installation media detected"
    log_function_exit 1
    return 1
}

# Clean up stale local repository configurations
# Removes installer-created repo files that point to non-existent mount points
cleanup_stale_local_repos() {
    log_function_entry

    local repo_pattern="/etc/yum.repos.d/local-rhel*.repo"
    local cleaned=0

    # Find all local-rhel*.repo files
    for repo_file in $repo_pattern; do
        # Skip if glob pattern didn't match any files
        [[ ! -f "$repo_file" ]] && continue

        # Check if this repo was created by our installer
        if grep -q "Created by NetBox Offline Installer" "$repo_file" 2>/dev/null; then
            log_debug "Found installer-created repo: $repo_file"

            # Extract mount point from repo file (line starting with "# Mount:")
            local mount_point
            mount_point=$(grep "^# Mount:" "$repo_file" 2>/dev/null | sed 's/^# Mount: //')

            if [[ -n "$mount_point" ]]; then
                # Check if mount point still exists and is accessible
                if [[ ! -d "$mount_point" ]] || [[ ! -d "$mount_point/BaseOS" ]]; then
                    log_warn "Stale repository configuration detected: $repo_file"
                    log_warn "Mount point no longer accessible: $mount_point"
                    log_info "Removing stale repository configuration..."
                    rm -f "$repo_file"
                    ((cleaned++))
                else
                    log_debug "Repository mount point still valid: $mount_point"
                fi
            fi
        fi
    done

    if [[ $cleaned -gt 0 ]]; then
        log_info "Cleaned $cleaned stale repository configuration(s)"
        # Update repository cache after cleanup
        dnf clean all &>/dev/null
    else
        log_debug "No stale repository configurations found"
    fi

    log_function_exit 0
    return 0
}

# Setup repository from mounted DVD
setup_local_repo_from_dvd() {
    local dvd_mount="$1"
    local repo_file="/etc/yum.repos.d/local-rhel.repo"

    log_function_entry
    log_info "Setting up local repository from mounted DVD: $dvd_mount"

    # Clean up any stale repository configurations first
    cleanup_stale_local_repos

    # Create repository configuration pointing to DVD mount point
    cat > "$repo_file" <<EOF
# Local RHEL repository from DVD
# Created by NetBox Offline Installer
# Mount: $dvd_mount

[local-rhel-baseos]
name=Local RHEL BaseOS (DVD)
baseurl=file://$dvd_mount/BaseOS
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[local-rhel-appstream]
name=Local RHEL AppStream (DVD)
baseurl=file://$dvd_mount/AppStream
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
EOF

    # Clean and update repository cache
    log_info "Updating repository cache..."
    dnf clean all &>/dev/null
    dnf makecache &>/dev/null

    # Verify repositories are accessible
    if dnf repolist 2>&1 | grep -q "local-rhel"; then
        log_info "Local repository configured successfully from DVD"
        log_function_exit 0
        return 0
    else
        log_error "Failed to configure local repository from DVD"
        log_function_exit 1
        return 1
    fi
}

# Prompt user to setup local repository if no repos available
prompt_for_local_repo_setup() {
    log_function_entry

    # Check if any repositories are available
    local repo_count
    repo_count=$(dnf repolist 2>/dev/null | grep -c "^[a-zA-Z]" || echo "0")

    if [[ "$repo_count" -eq 0 ]]; then
        log_warn "No YUM/DNF repositories configured on this system"
        log_warn "This is common on air-gapped or STIG-hardened systems"
        echo

        # Try to auto-detect mounted DVD first
        log_info "Checking for RHEL installation DVD..."
        local dvd_path
        if dvd_path=$(detect_rhel_dvd); then
            log_info "Found RHEL installation media: $dvd_path"
            echo

            if confirm_action "Use detected RHEL DVD to setup local repository?" "y"; then
                setup_local_repo_from_dvd "$dvd_path"
                log_function_exit $?
                return $?
            fi
        else
            log_info "No RHEL DVD detected in optical drive"
        fi

        # If no DVD or user declined, ask for ISO file path
        echo
        log_info "You can setup a local repository from a RHEL ISO file"
        echo

        if confirm_action "Do you have a RHEL installation ISO file?" "n"; then
            echo
            read -r -p "Enter full path to RHEL ISO file: " iso_path
            echo

            if [[ -n "$iso_path" ]]; then
                setup_local_repo_from_iso "$iso_path"
                log_function_exit $?
                return $?
            else
                log_warn "No ISO path provided, skipping local repository setup"
            fi
        else
            log_warn "Continuing without local repository"
            log_warn "Some package installations may fail"
        fi
    fi

    log_function_exit 0
    return 0
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize common module
init_common() {
    # Set up signal handlers
    setup_signal_handlers

    log_debug "Common module initialized"
}

# Auto-initialize when sourced
init_common

# End of common.sh
