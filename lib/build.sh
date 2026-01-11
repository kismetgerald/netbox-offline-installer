#!/bin/bash
#
# NetBox Offline Installer - Build Module
# Version: 0.0.1
# Description: Build offline installation package on internet-connected machine
#
# Created by: Kismet Agbasi (KismetG17@gmail.com)
# AI Collaborator: Claude Code (integrated with VS Code)
# Date Created: 12/27/2025
# Last Updated: 01/11/2026
#
# This module runs on an online RHEL 8/9/10 system with internet access and:
# - Queries GitHub API for latest stable NetBox release
# - Downloads NetBox source tarball
# - Collects all Python dependencies (wheels)
# - Collects all RPM dependencies
# - Packages everything into a portable offline installer
#

# =============================================================================
# BUILD CONFIGURATION
# =============================================================================

# Build workspace directory
# Use /var/tmp instead of /tmp to avoid STIG noexec restrictions
BUILD_WORKSPACE="${BUILD_WORKSPACE:-/var/tmp/netbox-offline-build}"

# Package output directory
BUILD_OUTPUT_DIR="${BUILD_OUTPUT_DIR:-./dist}"

# GitHub API configuration
GITHUB_API_URL="https://api.github.com/repos/netbox-community/netbox"
GITHUB_RELEASES_URL="${GITHUB_API_URL}/releases"

# NetBox repository URL
NETBOX_REPO_URL="https://github.com/netbox-community/netbox"

# Python version requirements
PYTHON_MIN_VERSION="3.10"

# =============================================================================
# GITHUB API INTEGRATION
# =============================================================================

# Query GitHub API for latest stable release
get_latest_netbox_version() {
    log_function_entry

    log_info "Querying GitHub API for latest NetBox release..."

    # Query releases API (returns JSON array)
    local releases_json
    if ! releases_json=$(curl -s -f "${GITHUB_RELEASES_URL}"); then
        log_error "Failed to query GitHub API"
        log_error "Check internet connectivity and GitHub API availability"
        log_function_exit 1
        return 1
    fi

    # Parse latest non-prerelease version
    # Filter out prereleases (beta, rc, etc.) and drafts
    local latest_version
    latest_version=$(echo "$releases_json" | \
        grep -v '"prerelease": true' | \
        grep -v '"draft": true' | \
        grep -oP '"tag_name": *"v\K[^"]+' | \
        head -1)

    if [[ -z "$latest_version" ]]; then
        log_error "Failed to parse latest version from GitHub API"
        log_function_exit 1
        return 1
    fi

    log_info "Latest stable NetBox version: v${latest_version}"
    echo "$latest_version"

    log_function_exit 0
    return 0
}

# Get download URL for specific NetBox version
get_netbox_download_url() {
    local version="$1"

    # Format: https://github.com/netbox-community/netbox/archive/refs/tags/vX.Y.Z.tar.gz
    echo "${NETBOX_REPO_URL}/archive/refs/tags/v${version}.tar.gz"
}

# Download NetBox source tarball
download_netbox_source() {
    local version="$1"
    local output_dir="$2"

    log_function_entry

    local download_url
    download_url=$(get_netbox_download_url "$version")

    local output_file="${output_dir}/netbox-${version}.tar.gz"

    log_info "Downloading NetBox v${version}..."
    log_info "URL: $download_url"
    log_info "Output: $output_file"

    # Download silently
    if curl -L -f -s --show-error -o "$output_file" "$download_url" 2>&1 | grep -i "error" >&2; then
        :  # Errors already shown
    fi

    # Check if download succeeded
    if [[ -f "$output_file" ]] && [[ -s "$output_file" ]]; then
        log_info "Download completed: $output_file"

        # Verify tarball integrity
        if tar -tzf "$output_file" &>/dev/null; then
            log_info "Tarball integrity verified"
            echo "$output_file"
            log_function_exit 0
            return 0
        else
            log_error "Downloaded tarball is corrupted"
            rm -f "$output_file"
            log_function_exit 1
            return 1
        fi
    else
        log_error "Failed to download NetBox source"
        log_function_exit 1
        return 1
    fi
}

# =============================================================================
# PYTHON DEPENDENCY COLLECTION
# =============================================================================

# Extract NetBox source and locate requirements file
extract_netbox_requirements() {
    local tarball="$1"
    local extract_dir="$2"

    log_function_entry

    log_info "Extracting NetBox source..."

    # Extract tarball
    if ! tar -xzf "$tarball" -C "$extract_dir"; then
        log_error "Failed to extract NetBox tarball"
        log_function_exit 1
        return 1
    fi

    # Find extracted directory (should be netbox-X.Y.Z)
    local netbox_dir
    netbox_dir=$(find "$extract_dir" -maxdepth 1 -type d -name "netbox-*" | head -1)

    if [[ -z "$netbox_dir" ]]; then
        log_error "Could not find extracted NetBox directory"
        log_debug "Contents of extract_dir: $(ls -la "$extract_dir")"
        log_function_exit 1
        return 1
    fi

    log_debug "Found NetBox directory: $netbox_dir"

    # Locate requirements.txt (NetBox has it in the root of the extracted archive)
    local requirements_file="${netbox_dir}/requirements.txt"

    # If not found at expected location, try searching recursively
    if [[ ! -f "$requirements_file" ]]; then
        log_debug "requirements.txt not found at: $requirements_file"
        log_debug "Searching for requirements.txt recursively..."
        requirements_file=$(find "$netbox_dir" -name "requirements.txt" -type f | head -1)

        if [[ -z "$requirements_file" || ! -f "$requirements_file" ]]; then
            log_error "requirements.txt not found in NetBox source"
            log_debug "Searched in: $netbox_dir"
            log_debug "Contents of netbox_dir: $(ls -la "$netbox_dir" | head -20)"
            log_function_exit 1
            return 1
        fi

        log_info "Found requirements file at alternate location: $requirements_file"
    fi

    log_info "Found requirements file: $requirements_file"

    # Count dependencies
    local dep_count
    dep_count=$(grep -v '^#' "$requirements_file" | grep -v '^$' | wc -l)
    log_info "NetBox has $dep_count Python dependencies"

    echo "$requirements_file"
    log_function_exit 0
    return 0
}

# Collect Python wheels for offline installation
collect_python_wheels() {
    local requirements_file="$1"
    local output_dir="$2"
    local target_python_version="${3:-}"  # Optional: specific Python version to use (e.g., "3.11")

    log_function_entry
    log_section "Collecting Python Dependencies"

    # Create output directory for wheels
    local wheels_dir="${output_dir}/wheels"
    mkdir -p "$wheels_dir"

    log_info "Collecting Python wheels for offline installation..."
    log_info "Requirements: $requirements_file"
    log_info "Output: $wheels_dir"

    # Detect Python version (check common locations)
    # Priority: /usr/local/bin (standalone Python) > system locations
    local python_cmd=""

    # If specific Python version requested, only search for that version
    if [[ -n "$target_python_version" ]]; then
        log_info "Target Python version: $target_python_version (enforced for consistency)"
        local pyver="python${target_python_version}"

        # Check /usr/local/bin first (standalone Python installations)
        if [[ -x "/usr/local/bin/$pyver" ]]; then
            python_cmd="/usr/local/bin/$pyver"
        # Then check system locations
        elif [[ -x "/usr/bin/$pyver" ]]; then
            python_cmd="/usr/bin/$pyver"
        # Finally check PATH
        elif command -v "$pyver" &>/dev/null; then
            python_cmd="$pyver"
        else
            log_error "Required Python $target_python_version not found"
            log_error "Searched locations: /usr/local/bin/$pyver, /usr/bin/$pyver, PATH"
            log_function_exit 1
            return 1
        fi
    else
        # No specific version requested, search for any Python 3.10+
        # Check for Python 3.10+ - prioritize /usr/local/bin where we install standalone Python
        for pyver in python3.12 python3.11 python3.10; do
            # Check /usr/local/bin first (standalone Python installations)
            if [[ -x "/usr/local/bin/$pyver" ]]; then
                python_cmd="/usr/local/bin/$pyver"
                break
            # Then check system locations
            elif [[ -x "/usr/bin/$pyver" ]]; then
                python_cmd="/usr/bin/$pyver"
                break
            # Finally check PATH (may find system Python)
            elif command -v "$pyver" &>/dev/null; then
                python_cmd="$pyver"
                break
            fi
        done

        # Fallback to python3 if no specific version found
        if [[ -z "$python_cmd" ]]; then
            if command -v python3 &>/dev/null; then
                python_cmd="python3"
            else
                log_error "No suitable Python 3 installation found"
                log_error "Required: Python ${PYTHON_MIN_VERSION}+"
                log_function_exit 1
                return 1
            fi
        fi
    fi

    local python_version
    python_version=$($python_cmd --version | awk '{print $2}')
    log_info "Using Python: $python_cmd (version $python_version)"

    # Verify Python version meets minimum requirement
    if ! version_compare "$python_version" ">=" "$PYTHON_MIN_VERSION"; then
        log_error "Python version too old: $python_version < $PYTHON_MIN_VERSION"
        log_function_exit 1
        return 1
    fi

    # If target version specified, verify exact match (major.minor)
    if [[ -n "$target_python_version" ]]; then
        local detected_major_minor
        detected_major_minor=$(echo "$python_version" | cut -d. -f1,2)
        if [[ "$detected_major_minor" != "$target_python_version" ]]; then
            log_error "Python version mismatch: found $python_version, expected $target_python_version"
            log_function_exit 1
            return 1
        fi
        log_info "Python version validated: $python_version matches target $target_python_version"
    fi

    # Upgrade pip to latest version
    log_info "Upgrading pip to latest version..."
    if ! $python_cmd -m pip install --upgrade pip &>/dev/null; then
        log_warn "Failed to upgrade pip, continuing with current version"
    fi

    # Install build dependencies required for building Python packages
    # psycopg[c] requires PostgreSQL development headers (pg_config)
    log_info "Installing build dependencies for Python packages..."

    # Note: DVD detection now happens earlier in collect_rpm_packages()
    # This ensures repositories are configured before all package operations

    log_debug "Installing libpq-devel for psycopg C extension..."
    if ! rpm -q libpq-devel &>/dev/null; then
        # Try to install libpq-devel (show error output if it fails)
        if dnf install -y libpq-devel 2>&1 | tee -a "$LOG_FILE" | grep -qi "error\|fail"; then
            log_warn "Failed to install libpq-devel, psycopg C extension may not build"
            log_warn "Will fall back to pure Python psycopg implementation"
        else
            log_debug "libpq-devel installed successfully"
        fi
    else
        log_debug "libpq-devel already installed"
    fi

    # Download all wheels with dependencies
    log_info "Downloading Python wheels (this may take several minutes)..."
    log_info "This will be silent - check log file for details: $LOG_FILE"

    # Download all packages (wheels preferred, source distributions as fallback)
    # Note: We let pip naturally select the appropriate versions based on the running Python interpreter
    # Some packages like django-pglocks only have source distributions, not wheels
    log_debug "Downloading packages (wheels preferred, source distributions as fallback)..."
    $python_cmd -m pip download \
        -r "$requirements_file" \
        -d "$wheels_dir" \
        >> "$LOG_FILE" 2>&1 || true

    # Download common build dependencies that may be needed for building source distributions
    # psycopg-c requires setuptools==80.3.1 and wheel to build
    log_debug "Downloading build dependencies (setuptools==80.3.1, wheel)..."
    $python_cmd -m pip download \
        'setuptools==80.3.1' \
        wheel \
        -d "$wheels_dir" \
        >> "$LOG_FILE" 2>&1 || true

    # Build wheels from source distributions
    log_info "Building wheels from source distributions (if any)..."
    local sdist_count
    sdist_count=$(find "$wheels_dir" -name "*.tar.gz" -o -name "*.zip" | wc -l)

    if [[ $sdist_count -gt 0 ]]; then
        log_debug "Found $sdist_count source distributions to build"

        # Build wheels from source distributions
        for sdist in "$wheels_dir"/*.tar.gz "$wheels_dir"/*.zip; do
            [[ -f "$sdist" ]] || continue

            local sdist_name
            sdist_name=$(basename "$sdist")
            log_debug "Building wheel for $sdist_name..."

            if $python_cmd -m pip wheel \
                --no-deps \
                --wheel-dir "$wheels_dir" \
                "$sdist" \
                >> "$LOG_FILE" 2>&1; then
                log_debug "Successfully built wheel for $sdist_name"
                # Remove the source distribution after successful wheel build
                rm -f "$sdist"
            else
                # Some packages need system libraries to build (e.g., psycopg_c needs libpq-devel)
                # This is expected - they'll be built during installation when dependencies are available
                if [[ "$sdist_name" =~ psycopg ]]; then
                    log_debug "$sdist_name requires PostgreSQL libraries (will build during installation)"
                else
                    log_debug "Could not build wheel for $sdist_name (will use source distribution)"
                fi
            fi
        done
    fi

    # Count collected wheels
    local wheel_count
    wheel_count=$(find "$wheels_dir" -name "*.whl" | wc -l)

    # Count remaining source distributions
    local remaining_sdist
    remaining_sdist=$(find "$wheels_dir" \( -name "*.tar.gz" -o -name "*.zip" \) | wc -l)

    if [[ $wheel_count -eq 0 && $remaining_sdist -eq 0 ]]; then
        log_error "Failed to download any Python packages"
        log_error "Check internet connectivity and PyPI availability"
        log_function_exit 1
        return 1
    fi

    log_info "Collected $wheel_count Python wheels"

    if [[ $remaining_sdist -gt 0 ]]; then
        log_info "Collected $remaining_sdist source distributions (will be built during installation)"
    fi

    # Calculate total size
    local total_size
    total_size=$(du -sh "$wheels_dir" | awk '{print $1}')
    log_info "Total package size: $total_size"

    log_function_exit 0
    return 0
}

# =============================================================================
# RPM DEPENDENCY COLLECTION
# =============================================================================

# Get list of required system packages
get_required_system_packages() {
    local rhel_version="$1"

    log_function_entry

    # Base system dependencies
    local base_packages=(
        "gcc"
        "gcc-c++"
        "make"
        "libxml2-devel"
        "libxslt-devel"
        "libffi-devel"
        "openssl-devel"
        "redhat-rpm-config"
        "git"
        "annobin"
        "gcc-plugin-annobin"
    )

    # PostgreSQL packages (always include for local mode support)
    # RHEL 8: PostgreSQL 15 via AppStream module (NetBox 4.x requires PostgreSQL 14+)
    # RHEL 9: PostgreSQL 15 via AppStream module (NetBox 4.x requires PostgreSQL 14+)
    # RHEL 10: PostgreSQL 16 is default
    local postgresql_packages=()
    if [[ "$rhel_version" == "8" ]]; then
        # RHEL 8 uses UNVERSIONED package names with AppStream modules
        # The postgresql:15 module stream determines the actual version installed
        postgresql_packages=(
            "postgresql-server"       # PostgreSQL server (version 15 from module:15)
            "postgresql-contrib"      # Contributed modules
            "postgresql-devel"        # Development headers
            "postgresql"              # PostgreSQL client and libpq
            "libpq"                   # PostgreSQL client library
            "libpq-devel"             # Development headers for libpq
        )
    elif [[ "$rhel_version" == "9" ]]; then
        # RHEL 9 uses UNVERSIONED package names with AppStream modules
        # The postgresql:15 module stream determines the actual version installed
        postgresql_packages=(
            "postgresql-server"       # PostgreSQL server (version 15 from module:15)
            "postgresql-contrib"      # Contributed modules
            "postgresql-devel"        # Development headers
            "postgresql"              # PostgreSQL client and libpq
            "libpq"                   # PostgreSQL client library
            "libpq-devel"             # Development headers for libpq
        )
    elif [[ "$rhel_version" == "10" ]]; then
        postgresql_packages=(
            "postgresql-server"       # PostgreSQL 16 (default in RHEL 10)
            "postgresql-contrib"
            "postgresql-devel"
            "postgresql"              # PostgreSQL client and libpq
            "libpq"                   # PostgreSQL client library
            "libpq-devel"             # Development headers
        )
    fi

    # Redis packages
    local redis_packages=(
        "redis"
    )

    # Nginx packages
    local nginx_packages=(
        "nginx"
    )

    # Python packages
    # RHEL 8: Python 3.11 (NetBox requires 3.10+, 3.11 recommended)
    # RHEL 9: Python 3.11 (default 3.9 too old)
    # RHEL 10: Python 3.12 (default, no explicit version needed)
    local python_packages=()
    if [[ "$rhel_version" == "8" ]]; then
        # RHEL 8 needs explicit Python 3.11 (default 3.6/3.8 too old)
        python_packages=(
            "python3.11"
            "python3.11-devel"
            "python3.11-pip"
        )
    elif [[ "$rhel_version" == "9" ]]; then
        # RHEL 9 needs explicit Python 3.11 (default 3.9 too old)
        python_packages=(
            "python3.11"
            "python3.11-devel"
            "python3.11-pip"
        )
    elif [[ "$rhel_version" == "10" ]]; then
        # RHEL 10 has Python 3.12 by default
        python_packages=(
            "python3"
            "python3-devel"
            "python3-pip"
        )
    fi

    # Combine all packages
    local all_packages=(
        "${base_packages[@]}"
        "${postgresql_packages[@]}"
        "${redis_packages[@]}"
        "${nginx_packages[@]}"
        "${python_packages[@]}"
    )

    # Return as space-separated list
    echo "${all_packages[@]}"

    log_function_exit 0
    return 0
}

# Collect RPM packages with dependencies
collect_rpm_packages() {
    local output_dir="$1"

    log_function_entry
    log_section "Collecting RPM Dependencies"

    # Create output directory for RPMs
    local rpms_dir="${output_dir}/rpms"
    mkdir -p "$rpms_dir"

    # Detect RHEL version
    local rhel_version
    rhel_version=$(get_rhel_version)

    log_info "Collecting RPM packages for RHEL ${rhel_version}..."
    log_info "Output: $rpms_dir"

    # Try to detect and setup local repository from DVD early
    # This ensures clean, working repos before package operations
    log_info "Checking for RHEL installation media..."
    local dvd_path
    if dvd_path=$(detect_rhel_dvd); then
        log_info "Found RHEL installation media at: $dvd_path"
        if setup_local_repo_from_dvd "$dvd_path"; then
            log_info "Local repository configured successfully"
        else
            log_warn "Failed to configure local repository from DVD"
        fi
    else
        log_debug "No RHEL DVD detected, using existing repositories"
    fi

    # Get required packages
    local required_packages
    required_packages=$(get_required_system_packages "$rhel_version")

    log_info "Required packages: $required_packages"

    # Check if yumdownloader is available
    if ! command -v yumdownloader &>/dev/null; then
        log_info "Installing yum-utils for yumdownloader..."
        if ! dnf install -y yum-utils >> "$LOG_FILE" 2>&1; then
            log_error "Failed to install yum-utils"
            log_function_exit 1
            return 1
        fi
    fi

    # Enable PostgreSQL module for RHEL 8 and 9 (required for PostgreSQL 15)
    if [[ "$rhel_version" == "8" ]] || [[ "$rhel_version" == "9" ]]; then
        log_info "Resetting PostgreSQL module for RHEL ${rhel_version}..."
        dnf module reset postgresql -y >> "$LOG_FILE" 2>&1 || true

        log_info "Enabling PostgreSQL 15 module for RHEL ${rhel_version}..."
        if ! dnf module enable postgresql:15 -y >> "$LOG_FILE" 2>&1; then
            log_error "Failed to enable PostgreSQL 15 module"
            log_function_exit 1
            return 1
        fi

        # Refresh dnf cache after enabling module
        log_info "Refreshing package cache..."
        dnf makecache >> "$LOG_FILE" 2>&1 || true
    fi

    # Download packages with all dependencies
    log_info "Downloading RPMs with dependencies (this may take several minutes)..."

    # Use yumdownloader with --resolve for dependency resolution
    if yumdownloader \
        --destdir="$rpms_dir" \
        --resolve \
        $required_packages \
        >> "$LOG_FILE" 2>&1; then

        # Count downloaded RPMs
        local rpm_count
        rpm_count=$(find "$rpms_dir" -name "*.rpm" | wc -l)
        log_info "Collected $rpm_count RPM packages"

        # Calculate total size
        local total_size
        total_size=$(du -sh "$rpms_dir" | awk '{print $1}')
        log_info "Total RPMs size: $total_size"

        log_function_exit 0
        return 0
    else
        log_error "Failed to download RPM packages"
        log_error "Check repository configuration and internet connectivity"
        log_function_exit 1
        return 1
    fi
}

# =============================================================================
# PACKAGE ASSEMBLY
# =============================================================================

# Create package directory structure
create_package_structure() {
    local package_dir="$1"

    log_function_entry

    log_info "Creating package directory structure..."

    # Create directory structure
    local directories=(
        "$package_dir"
        "$package_dir/netbox-source"
        "$package_dir/wheels"
        "$package_dir/rpms"
        "$package_dir/lib"
        "$package_dir/config"
        "$package_dir/templates"
        "$package_dir/docs"
    )

    for dir in "${directories[@]}"; do
        if ! mkdir -p "$dir"; then
            log_error "Failed to create directory: $dir"
            log_function_exit 1
            return 1
        fi
    done

    log_info "Package structure created: $package_dir"
    log_function_exit 0
    return 0
}

# Copy installer scripts to package
copy_installer_scripts() {
    local package_dir="$1"
    local script_dir="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"

    log_function_entry

    log_info "Copying installer scripts to package..."

    # Copy library modules
    if [[ -d "$script_dir/lib" ]]; then
        cp -r "$script_dir/lib"/* "$package_dir/lib/" || {
            log_error "Failed to copy lib/ directory"
            log_function_exit 1
            return 1
        }
        log_info "Copied library modules"
    fi

    # Copy configuration templates
    if [[ -d "$script_dir/config" ]]; then
        cp -r "$script_dir/config"/* "$package_dir/config/" || {
            log_error "Failed to copy config/ directory"
            log_function_exit 1
            return 1
        }
        log_info "Copied configuration files"
    fi

    # Copy templates
    if [[ -d "$script_dir/templates" ]]; then
        cp -r "$script_dir/templates"/* "$package_dir/templates/" || {
            log_error "Failed to copy templates/ directory"
            log_function_exit 1
            return 1
        }
        log_info "Copied configuration templates"
    fi

    # Copy main installer script
    if [[ -f "$script_dir/netbox-installer.sh" ]]; then
        cp "$script_dir/netbox-installer.sh" "$package_dir/" || {
            log_error "Failed to copy netbox-installer.sh"
            log_function_exit 1
            return 1
        }
        chmod +x "$package_dir/netbox-installer.sh"
        log_info "Copied main installer script"
    fi

    # Copy documentation
    for doc in README.md ARCHITECTURE.md CHANGELOG.md; do
        if [[ -f "$script_dir/$doc" ]]; then
            cp "$script_dir/$doc" "$package_dir/docs/" 2>/dev/null
        fi
    done

    log_info "Installer scripts copied successfully"
    log_function_exit 0
    return 0
}

# Generate package manifest
generate_package_manifest() {
    local package_dir="$1"
    local netbox_version="$2"
    local rhel_version="$3"

    log_function_entry

    local manifest_file="${package_dir}/manifest.txt"

    log_info "Generating package manifest..."

    # Generate manifest content
    {
        echo "================================================================================"
        echo "NetBox Offline Installer Package Manifest"
        echo "================================================================================"
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "Build Host: $(hostname)"
        echo "Build User: $(whoami)"
        echo
        echo "Package Information:"
        echo "  NetBox Version:    v${netbox_version}"
        echo "  RHEL Version:      ${rhel_version}"
        echo "  RHEL Full Version: $(get_rhel_full_version)"
        echo "  Installer Version: ${INSTALLER_VERSION}"
        echo ""
        echo "Component Versions:"
        # Determine Python and PostgreSQL versions based on RHEL version
        local python_ver postgresql_ver
        case "$rhel_version" in
            8)
                python_ver="3.11"
                postgresql_ver="15"
                ;;
            9)
                python_ver="3.11"
                postgresql_ver="15"
                ;;
            10)
                python_ver="3.12"
                postgresql_ver="16"
                ;;
        esac
        echo "  Python Version:    ${python_ver}"
        echo "  PostgreSQL Version: ${postgresql_ver}"
        echo
        echo "Package Contents:"
        echo "--------------------------------------------------------------------------------"

        # Count components
        local rpm_count wheel_count
        rpm_count=$(find "$package_dir/rpms" -name "*.rpm" 2>/dev/null | wc -l)
        wheel_count=$(find "$package_dir/wheels" -name "*.whl" 2>/dev/null | wc -l)

        echo "  RPM Packages:      $rpm_count"
        echo "  Python Wheels:     $wheel_count"
        echo "  NetBox Source:     netbox-${netbox_version}.tar.gz"
        echo
        echo "Directory Sizes:"
        echo "--------------------------------------------------------------------------------"

        for dir in rpms wheels netbox-source lib config templates; do
            if [[ -d "$package_dir/$dir" ]]; then
                local size
                size=$(du -sh "$package_dir/$dir" 2>/dev/null | awk '{print $1}')
                printf "  %-20s %s\n" "$dir/" "$size"
            fi
        done

        echo
        echo "Total Package Size:"
        echo "--------------------------------------------------------------------------------"
        local total_size
        total_size=$(du -sh "$package_dir" | awk '{print $1}')
        echo "  $total_size"

        echo
        echo "================================================================================"
        echo "Component Details"
        echo "================================================================================"
        echo
        echo "RPM Packages (${rpm_count} total):"
        echo "--------------------------------------------------------------------------------"
        find "$package_dir/rpms" -name "*.rpm" -exec basename {} \; | sort

        echo
        echo "Python Wheels (${wheel_count} total):"
        echo "--------------------------------------------------------------------------------"
        find "$package_dir/wheels" -name "*.whl" -exec basename {} \; | sort

        echo
        echo "================================================================================"

    } > "$manifest_file"

    log_info "Manifest generated: $manifest_file"
    log_function_exit 0
    return 0
}

# Generate checksums for package verification
generate_package_checksums() {
    local package_dir="$1"

    log_function_entry

    local checksums_file="${package_dir}/checksums.txt"

    log_info "Generating SHA256 checksums..."

    # Generate checksums for all files in package
    (
        cd "$package_dir" || exit 1

        # Find all files except checksums.txt itself
        find . -type f ! -name "checksums.txt" ! -path "./checksums.txt" -exec sha256sum {} \; | \
            sort -k2 > checksums.txt

    ) || {
        log_error "Failed to generate checksums"
        log_function_exit 1
        return 1
    }

    local checksum_count
    checksum_count=$(wc -l < "$checksums_file")
    log_info "Generated checksums for $checksum_count files"
    log_security "Package checksums generated: $checksums_file"

    log_function_exit 0
    return 0
}

# Create final package tarball
create_package_tarball() {
    local package_dir="$1"
    local netbox_version="$2"
    local rhel_version="$3"
    local output_dir="$4"

    log_function_entry

    # Generate tarball filename
    local tarball_name="netbox-offline-rhel${rhel_version}-v${netbox_version}.tar.gz"
    local tarball_path="${output_dir}/${tarball_name}"

    log_info "Creating package tarball..."
    log_info "Output: $tarball_path"

    # Create output directory
    mkdir -p "$output_dir"

    # Create tarball
    local package_basename
    package_basename=$(basename "$package_dir")

    if tar -czf "$tarball_path" \
        -C "$(dirname "$package_dir")" \
        "$package_basename" \
        2>&1 | tee -a "$LOG_FILE"; then

        # Verify tarball
        if tar -tzf "$tarball_path" &>/dev/null; then
            local tarball_size
            tarball_size=$(du -sh "$tarball_path" | awk '{print $1}')

            log_info "Package tarball created successfully"
            log_info "Size: $tarball_size"
            log_info "Location: $tarball_path"

            # Generate checksum for tarball
            local checksum
            checksum=$(sha256sum "$tarball_path" | awk '{print $1}')
            echo "$checksum  $tarball_name" > "${tarball_path}.sha256"

            log_info "SHA256: $checksum"
            log_security "Package tarball checksum: ${tarball_path}.sha256"

            echo "$tarball_path"
            log_function_exit 0
            return 0
        else
            log_error "Created tarball is corrupted"
            log_function_exit 1
            return 1
        fi
    else
        log_error "Failed to create package tarball"
        log_function_exit 1
        return 1
    fi
}

# =============================================================================
# BUILD ORCHESTRATION
# =============================================================================

# Main build function
build_offline_package() {
    # Check for version in: 1) parameter, 2) environment variable, 3) default to "latest"
    local netbox_version="${1:-${NETBOX_VERSION:-latest}}"

    log_function_entry
    log_section "NetBox Offline Package Build"

    # Debug: Log version selection
    log_debug "Version selection: parameter=\${1}='${1}', NETBOX_VERSION='${NETBOX_VERSION}', final='${netbox_version}'"

    # Pre-flight checks
    log_subsection "Pre-flight Checks"

    # Check root user
    check_root_user

    # Check internet connectivity
    if ! verify_internet_connectivity; then
        log_error "Build mode requires internet connectivity"
        log_function_exit 1
        return 1
    fi

    # Detect RHEL version
    local rhel_version
    rhel_version=$(check_supported_os)

    log_info "Building for RHEL ${rhel_version}"

    # Check disk space (need at least 5GB)
    # Use /var for build workspace (STIG-compliant: /tmp and /var/tmp have noexec)
    if ! check_disk_space "/var" "$MIN_DISK_SPACE_GB"; then
        log_error "Insufficient disk space for build"
        log_error "Build workspace requires ${MIN_DISK_SPACE_GB}GB on /var"
        log_function_exit 1
        return 1
    fi

    # Check for repositories and prompt to setup local repo if none available
    prompt_for_local_repo_setup

    # Ensure Python 3.11+ is installed (required for NetBox and wheel collection)
    log_info "Ensuring Python 3.11+ is available..."
    if ! command -v python3.11 &>/dev/null && ! command -v python3.12 &>/dev/null; then
        log_info "Python 3.11+ not found, attempting to install..."

        # Check if EPEL repository is available
        if ! dnf repolist 2>/dev/null | grep -qi epel; then
            log_info "EPEL repository not found, installing EPEL release..."
            if ! dnf install -y epel-release &>>"$LOG_FILE"; then
                log_warn "Failed to install EPEL from repositories"
                log_info "Attempting to install EPEL manually for RHEL ${rhel_version}..."

                # Download and install EPEL release RPM directly
                local epel_rpm_url
                if [[ "$rhel_version" == "8" ]]; then
                    epel_rpm_url="https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm"
                elif [[ "$rhel_version" == "9" ]]; then
                    epel_rpm_url="https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm"
                elif [[ "$rhel_version" == "10" ]]; then
                    epel_rpm_url="https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm"
                else
                    log_error "Unsupported RHEL version for EPEL: ${rhel_version}"
                    log_error "Cannot install Python 3.11 without EPEL repository"
                    log_function_exit 1
                    return 1
                fi

                log_info "Downloading EPEL release from: $epel_rpm_url"

                # Download EPEL RPM to temporary location
                local epel_rpm_file="/tmp/epel-release.rpm"
                if ! curl -L -f -s -o "$epel_rpm_file" "$epel_rpm_url"; then
                    log_error "Failed to download EPEL release RPM"
                    log_error "URL: $epel_rpm_url"
                    log_error "Check internet connectivity"
                    log_function_exit 1
                    return 1
                fi

                log_info "Installing EPEL release RPM..."
                if ! rpm -ivh "$epel_rpm_file" &>>"$LOG_FILE"; then
                    # Check if already installed
                    if rpm -q epel-release &>/dev/null; then
                        log_info "EPEL release already installed"
                    else
                        log_error "Failed to install EPEL repository RPM"
                        log_error "Check log file for details: $LOG_FILE"
                        rm -f "$epel_rpm_file"
                        log_function_exit 1
                        return 1
                    fi
                fi

                # Clean up downloaded RPM
                rm -f "$epel_rpm_file"
            fi
            log_info "EPEL repository installed successfully"
        else
            log_info "EPEL repository already available"
        fi

        # Try to find and install available Python 3.10+ package
        log_info "Searching for available Python 3.10+ packages..."

        # Check what Python 3.x versions are available
        local available_python=""
        for pyver in python3.12 python3.11 python3.10; do
            if dnf list available "$pyver" &>>"$LOG_FILE" 2>&1; then
                available_python="$pyver"
                break
            fi
        done

        if [[ -n "$available_python" ]]; then
            log_info "Found available package: $available_python"
            log_info "Installing $available_python with pip and devel packages..."
            if ! dnf install -y "$available_python" "${available_python}-pip" "${available_python}-devel" &>>"$LOG_FILE"; then
                log_warn "Failed to install some $available_python packages, trying base package only..."
                if ! dnf install -y "$available_python" &>>"$LOG_FILE"; then
                    log_error "Failed to install $available_python"
                    log_function_exit 1
                    return 1
                fi
            fi
            log_info "$available_python installed successfully"
        else
            log_warn "No Python 3.10+ packages found in repositories"
            log_info "Downloading Python 3.11 from python-build-standalone project..."

            # Use python-build-standalone (pre-compiled Python, no system dependencies)
            # Project: https://github.com/indygreg/python-build-standalone
            # Maintained by Gregory Szorc, widely used in production environments
            local python_standalone_url="https://github.com/indygreg/python-build-standalone/releases/download/20241016/cpython-3.11.10%2B20241016-x86_64-unknown-linux-gnu-install_only.tar.gz"
            local python_dir="/usr/local/python3.11"
            local download_file="/tmp/python3.11-standalone.tar.gz"

            log_info "Downloading Python 3.11 standalone build (~50MB, no dependencies required)..."
            if ! curl -L -f -s --show-error -o "$download_file" "$python_standalone_url" 2>&1 | \
                 grep -i "error" >&2; then
                :  # Silent success
            fi

            # Check if download succeeded
            if [[ ! -f "$download_file" ]] || [[ ! -s "$download_file" ]]; then
                log_error "Failed to download Python 3.11 standalone build"
                log_error "Cannot proceed without Python 3.11+"
                rm -f "$download_file"
                log_function_exit 1
                return 1
            fi

            log_info "Extracting Python 3.11 to $python_dir..."
            mkdir -p "$python_dir"
            if ! tar -xzf "$download_file" -C "$python_dir" --strip-components=1; then
                log_error "Failed to extract Python 3.11"
                rm -f "$download_file"
                rm -rf "$python_dir"
                log_function_exit 1
                return 1
            fi

            # Create symlinks in /usr/local/bin
            log_info "Creating Python 3.11 symlinks..."
            ln -sf "${python_dir}/bin/python3.11" /usr/local/bin/python3.11
            ln -sf "${python_dir}/bin/pip3.11" /usr/local/bin/pip3.11

            # Configure FAPolicyD trust rules if active
            if systemctl is-active --quiet fapolicyd 2>/dev/null; then
                log_info "Configuring FAPolicyD trust rules for Python 3.11..."

                # Add Python directory to trusted paths
                if command -v fapolicyd-cli &>/dev/null; then
                    # Trust the Python installation directory
                    fapolicyd-cli --file add "$python_dir" &>/dev/null || true
                    fapolicyd-cli --file add /usr/local/bin/python3.11 &>/dev/null || true
                    fapolicyd-cli --file add /usr/local/bin/pip3.11 &>/dev/null || true
                    fapolicyd-cli --update &>/dev/null || true
                fi

                # Create custom FAPolicyD rule for Python standalone build
                local fapolicyd_rules_file="/etc/fapolicyd/rules.d/41-python-standalone.rules"
                log_debug "Creating FAPolicyD rule: $fapolicyd_rules_file"

                cat > "$fapolicyd_rules_file" <<EOF
# FAPolicyD rules for Python standalone build (python-build-standalone)
# Created by NetBox Offline Installer
# Purpose: Allow execution of Python 3.11 from /usr/local/python3.11 and build workspace

# Allow execution of Python binaries
allow perm=any all : path=/usr/local/python3.11/bin/ ftype=application/x-executable trust=1
allow perm=any all : path=/usr/local/bin/python3.11 ftype=application/x-symlink trust=1
allow perm=any all : path=/usr/local/bin/pip3.11 ftype=application/x-symlink trust=1

# Allow loading of Python shared libraries
allow perm=any all : path=/usr/local/python3.11/lib/ ftype=application/x-sharedlib trust=1

# Allow Python to execute its own modules
allow perm=execute all : dir=/usr/local/python3.11/ all trust=1

# Allow Python to work in build workspace
allow perm=any all : dir=/var/tmp/netbox-offline-build/ all trust=1
allow perm=any all : dir=/tmp/ all trust=1
EOF

                # Reload FAPolicyD to apply new rules
                log_debug "Reloading FAPolicyD to apply new rules..."
                systemctl reload fapolicyd 2>/dev/null || systemctl restart fapolicyd 2>/dev/null || true

                log_info "FAPolicyD trust rules configured for Python 3.11"
            fi

            # Set SELinux contexts if SELinux is installed
            if command -v chcon &>/dev/null && [[ -d /sys/fs/selinux ]]; then
                log_info "Setting SELinux contexts for Python 3.11..."

                # Add permanent file context policies
                if command -v semanage &>/dev/null; then
                    log_debug "Adding SELinux file context policies..."
                    # Libraries need lib_t type for loading
                    semanage fcontext -a -t lib_t "${python_dir}/lib(/.*)?" &>/dev/null || \
                        semanage fcontext -m -t lib_t "${python_dir}/lib(/.*)?" &>/dev/null || true
                    # Executables need bin_t type
                    semanage fcontext -a -t bin_t "${python_dir}/bin(/.*)?" &>/dev/null || \
                        semanage fcontext -m -t bin_t "${python_dir}/bin(/.*)?" &>/dev/null || true
                    semanage fcontext -a -t bin_t "/usr/local/bin/python3\.11" &>/dev/null || \
                        semanage fcontext -m -t bin_t "/usr/local/bin/python3\.11" &>/dev/null || true
                    semanage fcontext -a -t bin_t "/usr/local/bin/pip3\.11" &>/dev/null || \
                        semanage fcontext -m -t bin_t "/usr/local/bin/pip3\.11" &>/dev/null || true
                fi

                # Apply contexts immediately with restorecon (preferred over chcon)
                if command -v restorecon &>/dev/null; then
                    restorecon -R "$python_dir" 2>/dev/null || true
                    restorecon /usr/local/bin/python3.11 /usr/local/bin/pip3.11 2>/dev/null || true
                else
                    # Fallback to chcon if restorecon unavailable
                    chcon -R -t lib_t "$python_dir/lib" 2>/dev/null || true
                    chcon -R -t bin_t "$python_dir/bin" 2>/dev/null || true
                    chcon -t bin_t /usr/local/bin/python3.11 /usr/local/bin/pip3.11 2>/dev/null || true
                fi

                log_info "SELinux contexts configured for Python 3.11"
            fi

            # Verify Python execution
            log_debug "Testing Python 3.11 execution..."
            if "$python_dir/bin/python3.11" --version &>/dev/null; then
                log_info "Python 3.11 executes successfully"
            else
                log_error "Python 3.11 execution still blocked after security configuration"
                log_error "Please check:"
                log_error "  - FAPolicyD logs: journalctl -u fapolicyd -n 50"
                log_error "  - SELinux denials: ausearch -m avc -ts recent"
                log_error "  - File permissions: ls -lZ $python_dir/bin/python3.11"
                log_function_exit 1
                return 1
            fi

            # Clean up download
            rm -f "$download_file"

            # Fix broken pip that comes with python-build-standalone
            # The bundled pip has a broken resolvelib module, so we need to replace it entirely
            log_info "Fixing pip installation (python-build-standalone has broken resolvelib)..."

            # Remove the broken pip directory completely
            log_debug "Removing broken pip from $python_dir/lib/python3.11/site-packages/pip"
            rm -rf "$python_dir/lib/python3.11/site-packages/pip" || true
            rm -rf "$python_dir/lib/python3.11/site-packages/pip-"*.dist-info || true

            # Download and run get-pip.py to install fresh pip
            local getpip_file="/tmp/get-pip.py"
            log_info "Downloading get-pip.py from PyPI..."
            if curl -s -f https://bootstrap.pypa.io/get-pip.py -o "$getpip_file" 2>&1 | grep -i "error" >&2; then
                log_error "Failed to download get-pip.py"
            fi

            if [[ -f "$getpip_file" && -s "$getpip_file" ]]; then
                log_info "Installing fresh pip from get-pip.py..."
                if "$python_dir/bin/python3.11" "$getpip_file" --force-reinstall &>/dev/null; then
                    log_info "Pip installed successfully"
                else
                    log_error "Failed to install pip via get-pip.py"
                    log_error "This will prevent wheel collection from working"
                fi
                rm -f "$getpip_file"
            else
                log_error "Failed to download get-pip.py"
                log_error "Cannot fix broken pip - wheel collection will fail"
            fi

            log_info "Python 3.11 installed successfully from standalone build"
            log_info "Location: $python_dir"
        fi
    else
        log_info "Python 3.11+ already available"
    fi

    # Optional: Pre-build STIG assessment
    run_stig_assessment "baseline"

    # Create build workspace
    log_subsection "Build Workspace"

    log_info "Creating build workspace: $BUILD_WORKSPACE"
    rm -rf "$BUILD_WORKSPACE"
    mkdir -p "$BUILD_WORKSPACE"

    # Configure security contexts for build workspace
    if command -v chcon &>/dev/null && [[ -d /sys/fs/selinux ]]; then
        log_debug "Setting SELinux contexts for build workspace..."
        # Use tmp_t context for /var/tmp workspace (allows Python to work)
        chcon -R -t tmp_t "$BUILD_WORKSPACE" 2>/dev/null || true
    fi

    # Add build workspace to FAPolicyD trust if active
    if systemctl is-active --quiet fapolicyd 2>/dev/null; then
        if command -v fapolicyd-cli &>/dev/null; then
            log_debug "Adding build workspace to FAPolicyD trust..."
            fapolicyd-cli --file add "$BUILD_WORKSPACE" &>/dev/null || true
            fapolicyd-cli --update &>/dev/null || true
        fi
    fi

    # Get NetBox version
    if [[ "$netbox_version" == "latest" ]]; then
        log_subsection "Querying Latest NetBox Version"
        netbox_version=$(get_latest_netbox_version) || {
            log_error "Failed to determine NetBox version"
            log_function_exit 1
            return 1
        }
    fi

    log_info "Building package for NetBox v${netbox_version}"

    # Download NetBox source
    log_subsection "NetBox Source Download"

    local netbox_tarball
    netbox_tarball=$(download_netbox_source "$netbox_version" "$BUILD_WORKSPACE") || {
        log_error "Failed to download NetBox source"
        log_function_exit 1
        return 1
    }

    # Extract and parse requirements
    local requirements_file
    requirements_file=$(extract_netbox_requirements "$netbox_tarball" "$BUILD_WORKSPACE") || {
        log_error "Failed to extract NetBox requirements"
        log_function_exit 1
        return 1
    }

    # Create package structure
    local package_name="netbox-offline-rhel${rhel_version}-v${netbox_version}"
    local package_dir="${BUILD_WORKSPACE}/${package_name}"

    create_package_structure "$package_dir" || {
        log_error "Failed to create package structure"
        log_function_exit 1
        return 1
    }

    # Determine target Python version for this RHEL version
    local target_python_version
    case "$rhel_version" in
        8|9)
            target_python_version="3.11"
            ;;
        10)
            target_python_version="3.12"
            ;;
        *)
            log_error "Unsupported RHEL version: $rhel_version"
            log_function_exit 1
            return 1
            ;;
    esac

    # Collect Python wheels (with enforced Python version for consistency)
    collect_python_wheels "$requirements_file" "$package_dir" "$target_python_version" || {
        log_error "Failed to collect Python wheels"
        log_function_exit 1
        return 1
    }

    # Collect RPM packages
    collect_rpm_packages "$package_dir" || {
        log_error "Failed to collect RPM packages"
        log_function_exit 1
        return 1
    }

    # Copy NetBox source to package
    log_subsection "Copying NetBox Source"
    cp "$netbox_tarball" "$package_dir/netbox-source/" || {
        log_error "Failed to copy NetBox source"
        log_function_exit 1
        return 1
    }
    log_info "NetBox source copied to package"

    # Copy installer scripts
    copy_installer_scripts "$package_dir" || {
        log_error "Failed to copy installer scripts"
        log_function_exit 1
        return 1
    }

    # Generate manifest
    generate_package_manifest "$package_dir" "$netbox_version" "$rhel_version" || {
        log_error "Failed to generate manifest"
        log_function_exit 1
        return 1
    }

    # Generate checksums
    generate_package_checksums "$package_dir" || {
        log_error "Failed to generate checksums"
        log_function_exit 1
        return 1
    }

    # Create final tarball
    log_subsection "Creating Package Tarball"

    local final_tarball
    final_tarball=$(create_package_tarball "$package_dir" "$netbox_version" "$rhel_version" "$BUILD_OUTPUT_DIR") || {
        log_error "Failed to create package tarball"
        log_function_exit 1
        return 1
    }

    # Build complete
    log_success_summary "Offline Package Build"
    log_info "NetBox version: v${netbox_version}"
    log_info "RHEL version: ${rhel_version}"
    log_info "Package location: $final_tarball"
    log_info "Checksum: ${final_tarball}.sha256"

    # Display manifest summary
    if [[ -f "$package_dir/manifest.txt" ]]; then
        log_subsection "Package Summary"

        # Display manifest with syslog-compliant formatting
        # Each line prefixed with [INFO] [timestamp] but preserving structure
        while IFS= read -r line; do
            log_info "$line"
        done < <(head -30 "$package_dir/manifest.txt")
    fi

    # Cleanup build workspace (optional)
    if confirm_action "Clean up build workspace?" "y"; then
        log_info "Cleaning up build workspace..."
        rm -rf "$BUILD_WORKSPACE"
        log_info "Build workspace cleaned"
    else
        log_info "Build workspace preserved: $BUILD_WORKSPACE"
    fi

    log_function_exit 0
    return 0
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize build module
init_build() {
    log_debug "Build module initialized"

    # Set default build workspace if not configured
    if [[ -z "${BUILD_WORKSPACE:-}" ]]; then
        export BUILD_WORKSPACE="/var/tmp/netbox-offline-build"
    fi

    # Set default output directory if not configured
    if [[ -z "${BUILD_OUTPUT_DIR:-}" ]]; then
        export BUILD_OUTPUT_DIR="./dist"
    fi
}

# Auto-initialize when sourced
init_build

# End of build.sh
