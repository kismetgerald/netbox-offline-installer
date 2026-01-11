#!/bin/bash
#
# NetBox Offline Package Validator
# Version: 0.0.1
# Description: Validates offline package structure, integrity, and completeness
#
# Created by: Kismet Agbasi (KismetG17@gmail.com)
# AI Collaborator: Claude Code (integrated with VS Code)
# Date Created: 12/27/2025
# Last Updated: 01/11/2026
#
# This script performs comprehensive validation of the built offline package
# before transferring to air-gapped networks. It checks:
#   - Package structure and required directories
#   - Checksum verification
#   - RPM package presence and counts
#   - Python wheel presence and counts
#   - RHEL version compatibility
#   - Manifest completeness
#   - NetBox version detection
#
# Usage:
#   ./validate-package.sh /path/to/extracted/package
#   ./validate-package.sh /path/to/netbox-offline-rhel9-v4.4.9.tar.gz
#

# =============================================================================
# SCRIPT INITIALIZATION
# =============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Validation results
VALIDATION_PASSED=0
VALIDATION_FAILED=0
VALIDATION_WARNINGS=0

# Colors for output
if [[ -t 1 ]]; then
    COLOR_GREEN='\033[0;32m'
    COLOR_RED='\033[0;31m'
    COLOR_YELLOW='\033[1;33m'
    COLOR_BLUE='\033[0;34m'
    COLOR_RESET='\033[0m'
else
    COLOR_GREEN=''
    COLOR_RED=''
    COLOR_YELLOW=''
    COLOR_BLUE=''
    COLOR_RESET=''
fi

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Display header
display_header() {
    echo
    echo "================================================================================"
    echo "              NetBox Offline Package Validator v0.0.1"
    echo "================================================================================"
    echo
}

# Log validation pass
log_pass() {
    local message="$*"
    echo -e "${COLOR_GREEN}[PASS]${COLOR_RESET} $message"
    ((VALIDATION_PASSED++))
}

# Log validation failure
log_fail() {
    local message="$*"
    echo -e "${COLOR_RED}[FAIL]${COLOR_RESET} $message"
    ((VALIDATION_FAILED++))
}

# Log validation warning
log_warn() {
    local message="$*"
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $message"
    ((VALIDATION_WARNINGS++))
}

# Log info message
log_info() {
    local message="$*"
    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $message"
}

# Display section header
display_section() {
    local section="$*"
    echo
    echo "--------------------------------------------------------------------------------"
    echo "$section"
    echo "--------------------------------------------------------------------------------"
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

# Validate package path
validate_package_path() {
    local package_path="$1"

    display_section "1. Package Path Validation"

    if [[ -z "$package_path" ]]; then
        log_fail "No package path provided"
        return 1
    fi

    # Check if path is a tarball
    if [[ -f "$package_path" && "$package_path" =~ \.tar\.gz$ ]]; then
        log_info "Package is compressed tarball: $package_path"

        # Check if extraction is needed
        if ! tar -tzf "$package_path" &>/dev/null; then
            log_fail "Tarball appears corrupted (cannot list contents)"
            return 1
        fi

        log_pass "Tarball is readable and appears valid"

        # Extract to temp directory
        local temp_dir
        temp_dir=$(mktemp -d -t netbox-validate.XXXXXXXXXX)

        log_info "Extracting package to: $temp_dir"

        if ! tar -xzf "$package_path" -C "$temp_dir" 2>/dev/null; then
            log_fail "Failed to extract tarball"
            rm -rf "$temp_dir"
            return 1
        fi

        log_pass "Package extracted successfully"

        # Find the extracted directory (should be only one)
        local extracted_dir
        extracted_dir=$(find "$temp_dir" -maxdepth 1 -type d ! -path "$temp_dir" | head -1)

        if [[ -z "$extracted_dir" ]]; then
            log_fail "No directory found in extracted tarball"
            rm -rf "$temp_dir"
            return 1
        fi

        # Update package path to extracted directory
        echo "$extracted_dir"
        return 0

    elif [[ -d "$package_path" ]]; then
        log_info "Package is directory: $package_path"
        log_pass "Directory exists and is accessible"
        echo "$package_path"
        return 0
    else
        log_fail "Package path does not exist or is not valid: $package_path"
        return 1
    fi
}

# Validate directory structure
validate_directory_structure() {
    local package_dir="$1"

    display_section "2. Directory Structure Validation"

    local required_dirs=(
        "rpms"
        "wheels"
        "netbox"
        "lib"
        "config"
    )

    local all_present=true

    for dir in "${required_dirs[@]}"; do
        if [[ -d "$package_dir/$dir" ]]; then
            log_pass "Directory exists: $dir/"
        else
            log_fail "Missing required directory: $dir/"
            all_present=false
        fi
    done

    # Check for required files
    local required_files=(
        "netbox-installer.sh"
        "config/defaults.conf"
        "config/install.conf.example"
    )

    for file in "${required_files[@]}"; do
        if [[ -f "$package_dir/$file" ]]; then
            log_pass "File exists: $file"
        else
            log_fail "Missing required file: $file"
            all_present=false
        fi
    done

    if [[ "$all_present" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# Validate manifest
validate_manifest() {
    local package_dir="$1"

    display_section "3. Manifest Validation"

    local manifest_file="$package_dir/manifest.txt"

    if [[ ! -f "$manifest_file" ]]; then
        log_fail "Manifest file not found: manifest.txt"
        return 1
    fi

    log_pass "Manifest file exists"

    # Check for required fields
    local required_fields=(
        "PACKAGE_VERSION"
        "NETBOX_VERSION"
        "RHEL_VERSION"
        "BUILD_DATE"
        "PYTHON_VERSION"
    )

    local all_fields_present=true

    for field in "${required_fields[@]}"; do
        if grep -q "^${field}=" "$manifest_file"; then
            local value
            value=$(grep "^${field}=" "$manifest_file" | cut -d'=' -f2-)
            log_pass "Field present: $field = $value"
        else
            log_fail "Missing manifest field: $field"
            all_fields_present=false
        fi
    done

    if [[ "$all_fields_present" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# Validate checksums
validate_checksums() {
    local package_dir="$1"

    display_section "4. Checksum Validation"

    local checksum_file="$package_dir/checksums.sha256"

    if [[ ! -f "$checksum_file" ]]; then
        log_warn "Checksum file not found: checksums.sha256 (optional)"
        return 0
    fi

    log_pass "Checksum file exists"

    # Validate checksums (if sha256sum is available)
    if command -v sha256sum &>/dev/null; then
        log_info "Verifying checksums..."

        if (cd "$package_dir" && sha256sum -c checksums.sha256 2>/dev/null); then
            log_pass "All checksums verified successfully"
            return 0
        else
            log_fail "Some checksums failed verification"
            return 1
        fi
    else
        log_warn "sha256sum command not available, skipping checksum verification"
        return 0
    fi
}

# Validate RPM packages
validate_rpm_packages() {
    local package_dir="$1"

    display_section "5. RPM Package Validation"

    local rpms_dir="$package_dir/rpms"

    if [[ ! -d "$rpms_dir" ]]; then
        log_fail "RPMs directory not found"
        return 1
    fi

    # Count RPM files
    local rpm_count
    rpm_count=$(find "$rpms_dir" -name "*.rpm" -type f | wc -l)

    if [[ $rpm_count -eq 0 ]]; then
        log_fail "No RPM packages found in rpms/"
        return 1
    fi

    log_pass "Found $rpm_count RPM packages"

    # Check for critical RPMs
    local critical_rpms=(
        "postgresql"
        "redis"
        "nginx"
        "gcc"
        "python3"
    )

    local all_critical_present=true

    for rpm_pattern in "${critical_rpms[@]}"; do
        if find "$rpms_dir" -name "${rpm_pattern}*.rpm" -type f | grep -q .; then
            local count
            count=$(find "$rpms_dir" -name "${rpm_pattern}*.rpm" -type f | wc -l)
            log_pass "Found $count ${rpm_pattern} package(s)"
        else
            log_warn "No RPM packages found matching pattern: ${rpm_pattern}*.rpm"
            all_critical_present=false
        fi
    done

    # Validate RPM integrity (if rpm command is available)
    if command -v rpm &>/dev/null; then
        log_info "Validating RPM package integrity..."

        local corrupt_rpms=0

        while IFS= read -r rpm_file; do
            if ! rpm -K "$rpm_file" &>/dev/null; then
                log_fail "Corrupt or invalid RPM: $(basename "$rpm_file")"
                ((corrupt_rpms++))
            fi
        done < <(find "$rpms_dir" -name "*.rpm" -type f)

        if [[ $corrupt_rpms -eq 0 ]]; then
            log_pass "All RPM packages passed integrity check"
        else
            log_fail "$corrupt_rpms RPM package(s) failed integrity check"
            return 1
        fi
    else
        log_warn "rpm command not available, skipping RPM integrity check"
    fi

    if [[ "$all_critical_present" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# Validate Python wheels
validate_python_wheels() {
    local package_dir="$1"

    display_section "6. Python Wheel Validation"

    local wheels_dir="$package_dir/wheels"

    if [[ ! -d "$wheels_dir" ]]; then
        log_fail "Wheels directory not found"
        return 1
    fi

    # Count wheel files
    local wheel_count
    wheel_count=$(find "$wheels_dir" -name "*.whl" -type f | wc -l)

    if [[ $wheel_count -eq 0 ]]; then
        log_fail "No Python wheel files found in wheels/"
        return 1
    fi

    log_pass "Found $wheel_count Python wheel files"

    # Check for critical Python packages
    local critical_wheels=(
        "Django"
        "gunicorn"
        "psycopg"
        "redis"
        "requests"
    )

    local all_critical_present=true

    for wheel_pattern in "${critical_wheels[@]}"; do
        if find "$wheels_dir" -name "${wheel_pattern}*.whl" -type f | grep -q .; then
            log_pass "Found wheel matching: ${wheel_pattern}"
        else
            log_warn "No wheel found matching pattern: ${wheel_pattern}*.whl"
            all_critical_present=false
        fi
    done

    # Minimum expected wheel count (NetBox typically has 40+ dependencies)
    local min_expected_wheels=30

    if [[ $wheel_count -lt $min_expected_wheels ]]; then
        log_warn "Wheel count ($wheel_count) is lower than expected minimum ($min_expected_wheels)"
    else
        log_pass "Wheel count meets minimum expectations ($wheel_count >= $min_expected_wheels)"
    fi

    if [[ "$all_critical_present" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# Validate NetBox source
validate_netbox_source() {
    local package_dir="$1"

    display_section "7. NetBox Source Validation"

    local netbox_dir="$package_dir/netbox"

    if [[ ! -d "$netbox_dir" ]]; then
        log_fail "NetBox directory not found"
        return 1
    fi

    log_pass "NetBox directory exists"

    # Check for critical NetBox files
    local critical_files=(
        "manage.py"
        "netbox/settings.py"
        "netbox/configuration_example.py"
        "base_requirements.txt"
    )

    local all_files_present=true

    for file in "${critical_files[@]}"; do
        if [[ -f "$netbox_dir/$file" ]]; then
            log_pass "NetBox file exists: $file"
        else
            log_fail "Missing critical NetBox file: $file"
            all_files_present=false
        fi
    done

    # Detect NetBox version from settings.py
    if [[ -f "$netbox_dir/netbox/settings.py" ]]; then
        local netbox_version
        netbox_version=$(grep -oP "VERSION\s*=\s*'\K[^']+" "$netbox_dir/netbox/settings.py" 2>/dev/null | head -1)

        if [[ -n "$netbox_version" ]]; then
            log_pass "Detected NetBox version: $netbox_version"
        else
            log_warn "Could not detect NetBox version from settings.py"
        fi
    fi

    if [[ "$all_files_present" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# Validate library modules
validate_library_modules() {
    local package_dir="$1"

    display_section "8. Library Module Validation"

    local lib_dir="$package_dir/lib"

    if [[ ! -d "$lib_dir" ]]; then
        log_fail "Library directory not found"
        return 1
    fi

    # Check for required library modules
    local required_modules=(
        "common.sh"
        "logging.sh"
        "credentials.sh"
        "security.sh"
        "build.sh"
        "install.sh"
        "update.sh"
        "rollback.sh"
        "uninstall.sh"
        "vm-snapshot.sh"
        "stig-assessment.sh"
    )

    local all_modules_present=true

    for module in "${required_modules[@]}"; do
        if [[ -f "$lib_dir/$module" ]]; then
            # Check if module is executable or at least readable
            if [[ -r "$lib_dir/$module" ]]; then
                log_pass "Library module exists and is readable: $module"
            else
                log_fail "Library module exists but is not readable: $module"
                all_modules_present=false
            fi
        else
            log_fail "Missing required library module: $module"
            all_modules_present=false
        fi
    done

    if [[ "$all_modules_present" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# Validate RHEL version compatibility
validate_rhel_compatibility() {
    local package_dir="$1"

    display_section "9. RHEL Version Compatibility"

    local manifest_file="$package_dir/manifest.txt"

    if [[ ! -f "$manifest_file" ]]; then
        log_warn "Cannot validate RHEL compatibility (manifest missing)"
        return 0
    fi

    # Extract RHEL version from manifest
    local package_rhel_version
    package_rhel_version=$(grep "^RHEL_VERSION=" "$manifest_file" | cut -d'=' -f2)

    if [[ -z "$package_rhel_version" ]]; then
        log_warn "RHEL version not specified in manifest"
        return 0
    fi

    log_info "Package built for RHEL version: $package_rhel_version"

    # Detect current system RHEL version (if running on RHEL)
    if [[ -f /etc/redhat-release ]]; then
        local current_rhel_version
        current_rhel_version=$(grep -oP 'release \K\d+' /etc/redhat-release 2>/dev/null | head -1)

        if [[ -n "$current_rhel_version" ]]; then
            log_info "Current system RHEL version: $current_rhel_version"

            if [[ "$package_rhel_version" == "$current_rhel_version" ]]; then
                log_pass "Package RHEL version matches current system"
            else
                log_warn "Package built for RHEL $package_rhel_version but current system is RHEL $current_rhel_version"
                log_warn "Binary compatibility issues may occur (RPMs and wheels are version-specific)"
            fi
        else
            log_warn "Could not detect current RHEL version for comparison"
        fi
    else
        log_info "Not running on RHEL system (validation system)"
        log_pass "Package RHEL version recorded: $package_rhel_version"
    fi

    return 0
}

# Display validation summary
display_validation_summary() {
    display_section "Validation Summary"

    echo
    echo "Results:"
    echo -e "  ${COLOR_GREEN}Passed:${COLOR_RESET}   $VALIDATION_PASSED"
    echo -e "  ${COLOR_RED}Failed:${COLOR_RESET}   $VALIDATION_FAILED"
    echo -e "  ${COLOR_YELLOW}Warnings:${COLOR_RESET} $VALIDATION_WARNINGS"
    echo

    if [[ $VALIDATION_FAILED -eq 0 ]]; then
        echo -e "${COLOR_GREEN}================================================================================"
        echo -e "                    VALIDATION PASSED"
        echo -e "================================================================================${COLOR_RESET}"
        echo
        echo "This package appears to be valid and ready for transfer to air-gapped network."
        echo
        return 0
    else
        echo -e "${COLOR_RED}================================================================================"
        echo -e "                    VALIDATION FAILED"
        echo -e "================================================================================${COLOR_RESET}"
        echo
        echo "This package has critical issues and should NOT be used for installation."
        echo "Please review the failures above and rebuild the package."
        echo
        return 1
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    display_header

    # Check arguments
    if [[ $# -eq 0 ]]; then
        echo "Usage: $0 <package-path>"
        echo
        echo "Examples:"
        echo "  $0 /path/to/netbox-offline-rhel9-v4.4.9.tar.gz"
        echo "  $0 /path/to/extracted/netbox-offline-rhel9-v4.4.9"
        echo
        exit 1
    fi

    local package_input="$1"

    # Validate and process package path
    local package_dir
    package_dir=$(validate_package_path "$package_input")
    local validation_result=$?

    if [[ $validation_result -ne 0 ]]; then
        echo
        echo "Package path validation failed. Exiting."
        exit 1
    fi

    # Run all validation checks
    validate_directory_structure "$package_dir"
    validate_manifest "$package_dir"
    validate_checksums "$package_dir"
    validate_rpm_packages "$package_dir"
    validate_python_wheels "$package_dir"
    validate_netbox_source "$package_dir"
    validate_library_modules "$package_dir"
    validate_rhel_compatibility "$package_dir"

    # Display summary
    display_validation_summary
    local summary_result=$?

    # Cleanup temp directory if we extracted
    if [[ "$package_input" =~ \.tar\.gz$ ]]; then
        local temp_parent
        temp_parent=$(dirname "$package_dir")
        if [[ "$temp_parent" =~ ^/tmp/netbox-validate ]]; then
            log_info "Cleaning up temporary directory: $temp_parent"
            rm -rf "$temp_parent"
        fi
    fi

    exit $summary_result
}

# Execute main function
main "$@"

# End of validate-package.sh
