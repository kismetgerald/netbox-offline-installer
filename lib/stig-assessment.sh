#!/bin/bash
#
# NetBox Offline Installer - STIG Assessment Integration
# Version: 0.0.1
# Description: Optional integration with Evaluate-STIG for compliance scanning
#
# Created by: Kismet Agbasi (KismetG17@gmail.com)
# AI Collaborator: Claude Code (integrated with VS Code)
# Date Created: 12/27/2025
# Last Updated: 01/11/2026
#
# IMPORTANT: This module does NOT bundle Evaluate-STIG due to licensing restrictions.
# Users must provide Evaluate-STIG separately if STIG scanning is desired.
#
# Evaluate-STIG is available from: https://public.cyber.mil/stigs/supplemental-automation-content/
#

# =============================================================================
# CONSTANTS
# =============================================================================

# Default STIG report directory
readonly DEFAULT_STIG_REPORT_DIR="/var/backup/netbox-offline-installer/stig-reports"

# Expected Evaluate-STIG script name
readonly EVALUATE_STIG_SCRIPT="evaluate-stig.sh"

# STIG report file naming
readonly STIG_BASELINE_PREFIX="stig-baseline"
readonly STIG_COMPLIANCE_PREFIX="stig-compliance"
readonly STIG_COMPARISON_PREFIX="stig-comparison"

# =============================================================================
# EVALUATE-STIG DETECTION
# =============================================================================

# Check if Evaluate-STIG is available
# Returns 0 if found, 1 if not found
is_evaluate_stig_available() {
    local stig_path="${1:-$EVALUATE_STIG_PATH}"

    log_function_entry

    # Check if path is provided
    if [[ -z "$stig_path" ]]; then
        log_debug "No EVALUATE_STIG_PATH configured"
        log_function_exit 1
        return 1
    fi

    # Check if file exists
    if [[ ! -f "$stig_path" ]]; then
        log_debug "Evaluate-STIG not found at: $stig_path"
        log_function_exit 1
        return 1
    fi

    # Check if executable
    if [[ ! -x "$stig_path" ]]; then
        log_warn "Evaluate-STIG found but not executable: $stig_path"
        log_warn "Run: chmod +x $stig_path"
        log_function_exit 1
        return 1
    fi

    # Verify it's actually Evaluate-STIG (basic sanity check)
    if ! grep -q "STIG" "$stig_path" 2>/dev/null; then
        log_warn "File at $stig_path does not appear to be Evaluate-STIG"
        log_function_exit 1
        return 1
    fi

    log_info "Evaluate-STIG found: $stig_path"
    log_function_exit 0
    return 0
}

# Detect Evaluate-STIG in common locations
find_evaluate_stig() {
    log_function_entry

    # List of common installation locations
    local search_paths=(
        "./evaluate-stig.sh"
        "./Evaluate-STIG/evaluate-stig.sh"
        "/opt/Evaluate-STIG/evaluate-stig.sh"
        "/usr/local/bin/evaluate-stig.sh"
        "$HOME/Evaluate-STIG/evaluate-stig.sh"
    )

    for path in "${search_paths[@]}"; do
        if is_evaluate_stig_available "$path"; then
            echo "$path"
            log_function_exit 0
            return 0
        fi
    done

    log_debug "Evaluate-STIG not found in common locations"
    log_function_exit 1
    return 1
}

# =============================================================================
# STIG REPORT DIRECTORY MANAGEMENT
# =============================================================================

# Initialize STIG report directory
init_stig_report_dir() {
    local report_dir="${1:-$STIG_REPORT_DIR}"

    log_function_entry

    # Use default if not provided
    report_dir="${report_dir:-$DEFAULT_STIG_REPORT_DIR}"

    # Create directory if doesn't exist
    if [[ ! -d "$report_dir" ]]; then
        log_info "Creating STIG report directory: $report_dir"

        if ! mkdir -p "$report_dir" 2>/dev/null; then
            log_error "Failed to create STIG report directory: $report_dir"
            log_function_exit 1
            return 1
        fi
    fi

    # Set secure permissions (640 - reports may contain sensitive info)
    chmod 750 "$report_dir" 2>/dev/null

    log_info "STIG report directory initialized: $report_dir"
    log_function_exit 0
    return 0
}

# Generate STIG report filename with timestamp
generate_stig_report_filename() {
    local report_type="$1"  # baseline, compliance, comparison
    local format="${2:-txt}"  # txt, html, json

    local timestamp
    timestamp=$(date '+%Y%m%d-%H%M%S')

    echo "${report_type}-${timestamp}.${format}"
}

# =============================================================================
# STIG ASSESSMENT EXECUTION
# =============================================================================

# Run Evaluate-STIG baseline assessment (pre-build)
run_stig_baseline() {
    local stig_path="${1:-$EVALUATE_STIG_PATH}"
    local output_dir="${2:-$STIG_REPORT_DIR}"

    log_function_entry
    log_section "STIG Baseline Assessment"

    # Check if Evaluate-STIG available
    if ! is_evaluate_stig_available "$stig_path"; then
        log_warn "Evaluate-STIG not available, skipping baseline assessment"
        log_info "To enable STIG scanning, install Evaluate-STIG and set EVALUATE_STIG_PATH"
        log_function_exit 1
        return 1
    fi

    # Initialize report directory
    if ! init_stig_report_dir "$output_dir"; then
        log_error "Failed to initialize STIG report directory"
        log_function_exit 1
        return 1
    fi

    # Generate report filename
    local report_file
    report_file=$(generate_stig_report_filename "$STIG_BASELINE_PREFIX" "txt")
    local report_path="${output_dir}/${report_file}"

    log_info "Running STIG baseline assessment..."
    log_info "Output: $report_path"
    log_info "This may take several minutes..."

    # Run Evaluate-STIG and capture output
    # Note: Evaluate-STIG outputs to stdout, redirect to file
    if "$stig_path" > "$report_path" 2>&1; then
        log_info "STIG baseline assessment completed successfully"
        log_security "STIG baseline report generated: $report_path"

        # Display summary statistics
        display_stig_summary "$report_path"

        log_function_exit 0
        return 0
    else
        log_error "STIG baseline assessment failed"
        log_error "Check report for details: $report_path"
        log_function_exit 1
        return 1
    fi
}

# Run Evaluate-STIG compliance assessment (post-install)
run_stig_compliance() {
    local stig_path="${1:-$EVALUATE_STIG_PATH}"
    local output_dir="${2:-$STIG_REPORT_DIR}"

    log_function_entry
    log_section "STIG Compliance Assessment"

    # Check if Evaluate-STIG available
    if ! is_evaluate_stig_available "$stig_path"; then
        log_warn "Evaluate-STIG not available, skipping compliance assessment"
        log_function_exit 1
        return 1
    fi

    # Initialize report directory
    if ! init_stig_report_dir "$output_dir"; then
        log_error "Failed to initialize STIG report directory"
        log_function_exit 1
        return 1
    fi

    # Generate report filename
    local report_file
    report_file=$(generate_stig_report_filename "$STIG_COMPLIANCE_PREFIX" "txt")
    local report_path="${output_dir}/${report_file}"

    log_info "Running STIG compliance assessment..."
    log_info "Output: $report_path"
    log_info "This may take several minutes..."

    # Run Evaluate-STIG
    if "$stig_path" > "$report_path" 2>&1; then
        log_info "STIG compliance assessment completed successfully"
        log_security "STIG compliance report generated: $report_path"

        # Display summary statistics
        display_stig_summary "$report_path"

        log_function_exit 0
        return 0
    else
        log_error "STIG compliance assessment failed"
        log_error "Check report for details: $report_path"
        log_function_exit 1
        return 1
    fi
}

# =============================================================================
# STIG REPORT ANALYSIS
# =============================================================================

# Display STIG report summary statistics
display_stig_summary() {
    local report_path="$1"

    if [[ ! -f "$report_path" ]]; then
        log_warn "Report file not found: $report_path"
        return 1
    fi

    log_subsection "STIG Assessment Summary"

    # Extract common STIG metrics (format may vary by Evaluate-STIG version)
    # These are typical patterns, adjust based on actual Evaluate-STIG output

    # Count findings by severity
    local cat1_count cat2_count cat3_count
    cat1_count=$(grep -c "CAT I" "$report_path" 2>/dev/null || echo "0")
    cat2_count=$(grep -c "CAT II" "$report_path" 2>/dev/null || echo "0")
    cat3_count=$(grep -c "CAT III" "$report_path" 2>/dev/null || echo "0")

    # Count findings by status
    local open_count notfound_count na_count
    open_count=$(grep -c "Open" "$report_path" 2>/dev/null || echo "0")
    notfound_count=$(grep -c "NotAFinding" "$report_path" 2>/dev/null || echo "0")
    na_count=$(grep -c "Not_Applicable" "$report_path" 2>/dev/null || echo "0")

    # Display results
    echo
    echo "Findings by Severity:"
    echo "  CAT I (High):   $cat1_count"
    echo "  CAT II (Medium): $cat2_count"
    echo "  CAT III (Low):   $cat3_count"
    echo
    echo "Findings by Status:"
    echo "  Open:           $open_count"
    echo "  Not a Finding:  $notfound_count"
    echo "  Not Applicable: $na_count"
    echo

    log_info "Full report available: $report_path"
}

# Compare baseline and compliance reports
compare_stig_reports() {
    local baseline_report="$1"
    local compliance_report="$2"
    local output_dir="${3:-$STIG_REPORT_DIR}"

    log_function_entry
    log_section "STIG Comparison Analysis"

    # Validate input files
    if [[ ! -f "$baseline_report" ]]; then
        log_error "Baseline report not found: $baseline_report"
        log_function_exit 1
        return 1
    fi

    if [[ ! -f "$compliance_report" ]]; then
        log_error "Compliance report not found: $compliance_report"
        log_function_exit 1
        return 1
    fi

    # Generate comparison report filename
    local comparison_file
    comparison_file=$(generate_stig_report_filename "$STIG_COMPARISON_PREFIX" "txt")
    local comparison_path="${output_dir}/${comparison_file}"

    log_info "Comparing STIG assessments..."
    log_info "Baseline:   $baseline_report"
    log_info "Compliance: $compliance_report"
    log_info "Output:     $comparison_path"

    # Create comparison report
    {
        echo "================================================================================"
        echo "STIG Assessment Comparison Report"
        echo "================================================================================"
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo
        echo "Baseline Report:   $baseline_report"
        echo "Compliance Report: $compliance_report"
        echo
        echo "================================================================================"
        echo "BASELINE ASSESSMENT"
        echo "================================================================================"
        echo
        display_stig_summary "$baseline_report"
        echo
        echo "================================================================================"
        echo "COMPLIANCE ASSESSMENT (POST-INSTALL)"
        echo "================================================================================"
        echo
        display_stig_summary "$compliance_report"
        echo
        echo "================================================================================"
        echo "ANALYSIS"
        echo "================================================================================"
        echo
        echo "This comparison shows the STIG compliance status before and after NetBox"
        echo "installation. Any new findings in the compliance report may be related to"
        echo "the NetBox installation and should be reviewed for remediation."
        echo
        echo "Note: The NetBox installer applies security hardening (SELinux, FAPolicyD,"
        echo "secure permissions) but cannot address all STIG requirements automatically."
        echo "Manual remediation may be required for some findings."
        echo
        echo "================================================================================"
    } > "$comparison_path"

    log_info "Comparison report generated: $comparison_path"
    log_security "STIG comparison analysis completed"

    log_function_exit 0
    return 0
}

# Find most recent STIG report of a given type
find_latest_stig_report() {
    local report_type="$1"  # baseline or compliance
    local output_dir="${2:-$STIG_REPORT_DIR}"

    # Find most recent report matching pattern
    local latest_report
    latest_report=$(find "$output_dir" -name "${report_type}-*.txt" -type f 2>/dev/null | sort -r | head -1)

    if [[ -n "$latest_report" && -f "$latest_report" ]]; then
        echo "$latest_report"
        return 0
    fi

    return 1
}

# =============================================================================
# STIG ASSESSMENT WORKFLOW
# =============================================================================

# Run STIG assessment based on configuration
run_stig_assessment() {
    local assessment_type="$1"  # baseline, compliance, or both
    local stig_path="${2:-$EVALUATE_STIG_PATH}"
    local output_dir="${3:-$STIG_REPORT_DIR}"

    log_function_entry

    # Check if STIG scanning is enabled
    local enable_stig="${ENABLE_STIG_SCAN:-auto}"

    case "${enable_stig,,}" in
        no|false|disabled)
            log_info "STIG scanning disabled in configuration"
            log_function_exit 0
            return 0
            ;;
        yes|true|enabled)
            # Required mode - fail if not available
            if ! is_evaluate_stig_available "$stig_path"; then
                log_error "STIG scanning enabled but Evaluate-STIG not found"
                log_error "Please install Evaluate-STIG or set ENABLE_STIG_SCAN=no"
                log_function_exit 1
                return 1
            fi
            ;;
        auto)
            # Optional mode - skip if not available
            if ! is_evaluate_stig_available "$stig_path"; then
                log_info "Evaluate-STIG not available, skipping STIG assessment"
                log_info "To enable STIG scanning:"
                log_info "  1. Download Evaluate-STIG from https://public.cyber.mil/stigs/"
                log_info "  2. Set EVALUATE_STIG_PATH in configuration"
                log_function_exit 0
                return 0
            fi
            ;;
        *)
            log_warn "Invalid ENABLE_STIG_SCAN value: $enable_stig (using 'auto')"
            enable_stig="auto"
            ;;
    esac

    # Run requested assessment type
    case "$assessment_type" in
        baseline)
            run_stig_baseline "$stig_path" "$output_dir"
            return $?
            ;;
        compliance)
            run_stig_compliance "$stig_path" "$output_dir"
            return $?
            ;;
        both|comparison)
            # Run both assessments and compare
            local baseline_report compliance_report

            if run_stig_baseline "$stig_path" "$output_dir"; then
                baseline_report=$(find_latest_stig_report "$STIG_BASELINE_PREFIX" "$output_dir")
            else
                log_error "Baseline assessment failed"
                log_function_exit 1
                return 1
            fi

            if run_stig_compliance "$stig_path" "$output_dir"; then
                compliance_report=$(find_latest_stig_report "$STIG_COMPLIANCE_PREFIX" "$output_dir")
            else
                log_error "Compliance assessment failed"
                log_function_exit 1
                return 1
            fi

            # Generate comparison if both reports exist
            if [[ -n "$baseline_report" && -n "$compliance_report" ]]; then
                compare_stig_reports "$baseline_report" "$compliance_report" "$output_dir"
            fi

            log_function_exit 0
            return 0
            ;;
        *)
            log_error "Invalid assessment type: $assessment_type"
            log_error "Valid types: baseline, compliance, both"
            log_function_exit 1
            return 1
            ;;
    esac
}

# =============================================================================
# STIG REPORT MANAGEMENT
# =============================================================================

# List all STIG reports
list_stig_reports() {
    local output_dir="${1:-$STIG_REPORT_DIR}"

    log_subsection "Available STIG Reports"

    if [[ ! -d "$output_dir" ]]; then
        log_info "No STIG reports found (directory doesn't exist)"
        return 0
    fi

    # Find all STIG reports
    local reports
    reports=$(find "$output_dir" -name "stig-*.txt" -type f 2>/dev/null | sort -r)

    if [[ -z "$reports" ]]; then
        log_info "No STIG reports found in $output_dir"
        return 0
    fi

    # Display reports
    echo
    echo "STIG Reports in $output_dir:"
    echo "----------------------------------------"

    while IFS= read -r report; do
        local filename
        filename=$(basename "$report")
        local filesize
        filesize=$(du -h "$report" 2>/dev/null | awk '{print $1}')
        local filedate
        filedate=$(stat -c '%y' "$report" 2>/dev/null | cut -d' ' -f1 || \
                   stat -f '%Sm' -t '%Y-%m-%d' "$report" 2>/dev/null)

        echo "  $filename"
        echo "    Date: $filedate  Size: $filesize"
    done <<< "$reports"

    echo "----------------------------------------"
    echo
}

# Clean up old STIG reports (keep last N)
cleanup_old_stig_reports() {
    local output_dir="${1:-$STIG_REPORT_DIR}"
    local retention="${2:-5}"  # Keep last 5 reports by default

    log_function_entry

    if [[ ! -d "$output_dir" ]]; then
        log_debug "STIG report directory doesn't exist, nothing to clean"
        log_function_exit 0
        return 0
    fi

    log_info "Cleaning up old STIG reports (keeping last $retention)"

    # Clean each report type separately
    for report_type in "$STIG_BASELINE_PREFIX" "$STIG_COMPLIANCE_PREFIX" "$STIG_COMPARISON_PREFIX"; do
        local old_reports
        old_reports=$(find "$output_dir" -name "${report_type}-*.txt" -type f 2>/dev/null | \
                      sort -r | tail -n +$((retention + 1)))

        if [[ -n "$old_reports" ]]; then
            echo "$old_reports" | while IFS= read -r report; do
                log_debug "Removing old STIG report: $report"
                rm -f "$report"
            done
        fi
    done

    log_info "STIG report cleanup completed"
    log_function_exit 0
    return 0
}

# =============================================================================
# DOCUMENTATION AND HELP
# =============================================================================

# Display STIG assessment information
display_stig_info() {
    cat <<'EOF'

================================================================================
STIG Assessment Integration
================================================================================

The NetBox Offline Installer includes optional integration with Evaluate-STIG
for DISA STIG compliance scanning.

IMPORTANT: Evaluate-STIG is NOT bundled with this installer due to licensing
restrictions. You must download and install it separately.

Where to Get Evaluate-STIG:
  https://public.cyber.mil/stigs/supplemental-automation-content/

Installation:
  1. Download Evaluate-STIG from the link above
  2. Extract to a directory (e.g., /opt/Evaluate-STIG)
  3. Make executable: chmod +x /opt/Evaluate-STIG/evaluate-stig.sh
  4. Set path in install.conf: EVALUATE_STIG_PATH="/opt/Evaluate-STIG/evaluate-stig.sh"

Assessment Types:
  Baseline    - Run before package build (documents initial state)
  Compliance  - Run after NetBox installation (documents final state)
  Comparison  - Compares baseline and compliance reports

Reports Location:
  Default: /var/backup/netbox-offline-installer/stig-reports
  Configurable via: STIG_REPORT_DIR in install.conf

Configuration Options:
  ENABLE_STIG_SCAN:
    auto - Run if Evaluate-STIG available (default)
    yes  - Require STIG scan (fail if not available)
    no   - Skip STIG scanning

Notes:
  - STIG scanning is optional and does not affect installation
  - Reports may contain sensitive system information (secure storage)
  - Manual remediation may be required for some STIG findings
  - NetBox installer applies security hardening but cannot address all STIGs

================================================================================

EOF
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize STIG assessment module
init_stig_assessment() {
    log_debug "STIG assessment module initialized"

    # Auto-detect Evaluate-STIG if not configured
    if [[ -z "${EVALUATE_STIG_PATH:-}" ]]; then
        local detected_path
        if detected_path=$(find_evaluate_stig); then
            log_debug "Auto-detected Evaluate-STIG: $detected_path"
            export EVALUATE_STIG_PATH="$detected_path"
        fi
    fi

    # Set default report directory if not configured
    if [[ -z "${STIG_REPORT_DIR:-}" ]]; then
        export STIG_REPORT_DIR="$DEFAULT_STIG_REPORT_DIR"
    fi
}

# Auto-initialize when sourced
init_stig_assessment

# End of stig-assessment.sh
