#!/bin/bash
#
# NetBox Offline Installer - Logging Framework
# Version: 0.0.1
# Description: Syslog-compliant logging with audit trail support
#
# Created by: Kismet Agbasi (KismetG17@gmail.com)
# AI Collaborator: Claude Code (integrated with VS Code)
# Date Created: 12/27/2025
# Last Updated: 01/11/2026
#

# =============================================================================
# LOGGING CONFIGURATION
# =============================================================================

# Default log file location
LOG_FILE="${LOG_FILE:-/var/log/netbox-offline-installer.log}"

# Default log level
LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Script name for logging
SCRIPT_NAME="netbox-installer"

# Log rotation threshold (10MB)
readonly LOG_ROTATION_THRESHOLD=$((10 * 1024 * 1024))

# =============================================================================
# LOG LEVEL DEFINITIONS
# =============================================================================

# Log level priorities (numeric for comparison)
declare -A LOG_LEVELS=(
    [DEBUG]=0
    [INFO]=1
    [WARN]=2
    [ERROR]=3
)

# ANSI color codes for console output
declare -A LOG_COLORS=(
    [DEBUG]="\033[0;37m"    # White
    [INFO]="\033[0;36m"     # Cyan (Light Blue)
    [SUCCESS]="\033[0;32m"  # Green
    [WARN]="\033[1;33m"     # Yellow (bright)
    [ERROR]="\033[0;31m"    # Red
    [RESET]="\033[0m"       # Reset
)

# =============================================================================
# CORE LOGGING FUNCTIONS
# =============================================================================

# Get current log level value
get_log_level_value() {
    echo "${LOG_LEVELS[$LOG_LEVEL]:-1}"
}

# Format timestamp (ISO 8601 with timezone)
get_timestamp() {
    date '+%Y-%m-%dT%H:%M:%S%:z'
}

# Core logging function
# Usage: log_message LEVEL "message"
log_message() {
    local level="$1"
    shift
    local message="$*"

    # Check if message should be logged based on level
    local current_level
    current_level=$(get_log_level_value)
    local message_level="${LOG_LEVELS[$level]:-1}"

    if [[ $message_level -lt $current_level ]]; then
        return 0
    fi

    # Format timestamp
    local timestamp
    timestamp=$(get_timestamp)

    # Get hostname
    local hostname
    hostname=$(hostname -s 2>/dev/null || echo "localhost")

    # Get PID
    local pid=$$

    # Format syslog-compliant log entry
    # Format: <timestamp> <hostname> <program>[<pid>]: <level> <message>
    local log_entry="${timestamp} ${hostname} ${SCRIPT_NAME}[${pid}]: ${level} ${message}"

    # Ensure log directory exists
    local log_dir
    log_dir=$(dirname "$LOG_FILE")
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" 2>/dev/null
    fi

    # Write to log file
    if [[ -w "$LOG_FILE" ]] || [[ -w "$log_dir" ]]; then
        echo "$log_entry" >> "$LOG_FILE" 2>/dev/null
    fi

    # Output to console with color and timestamp
    local color="${LOG_COLORS[$level]}"
    local reset="${LOG_COLORS[RESET]}"
    local console_timestamp
    console_timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        DEBUG)
            echo -e "${color}[DEBUG]${reset} [$console_timestamp] $message" >&2
            ;;
        INFO)
            echo -e "${color}[INFO]${reset} [$console_timestamp] $message" >&2
            ;;
        SUCCESS)
            echo -e "${color}[SUCCESS]${reset} [$console_timestamp] $message" >&2
            ;;
        WARN)
            echo -e "${color}[WARN]${reset} [$console_timestamp] $message" >&2
            ;;
        ERROR)
            echo -e "${color}[ERROR]${reset} [$console_timestamp] $message" >&2
            ;;
    esac
}

# =============================================================================
# CONVENIENCE LOGGING FUNCTIONS
# =============================================================================

# Log debug message
log_debug() {
    log_message DEBUG "$@"
}

# Log info message
log_info() {
    log_message INFO "$@"
}

# Log success message
log_success() {
    log_message SUCCESS "$@"
}

# Log warning message
log_warn() {
    log_message WARN "$@"
}

# Log error message
log_error() {
    log_message ERROR "$@"
}

# =============================================================================
# FUNCTION ENTRY/EXIT LOGGING
# =============================================================================

# Log function entry
log_function_entry() {
    local func_name="${FUNCNAME[1]}"
    log_debug "Entering function: ${func_name}"
}

# Log function exit
log_function_exit() {
    local exit_code="${1:-0}"
    local func_name="${FUNCNAME[1]}"

    if [[ $exit_code -eq 0 ]]; then
        log_debug "Exiting function: ${func_name} (success)"
    else
        log_debug "Exiting function: ${func_name} (exit code: $exit_code)"
    fi
}

# =============================================================================
# COMMAND OUTPUT CAPTURE AND LOGGING
# =============================================================================

# Sanitize output to remove sensitive information
sanitize_log_output() {
    local output="$1"

    # Redact common password patterns
    output=$(echo "$output" | sed -E 's/(password|passwd|pwd)=[^ ]*/\1=***REDACTED***/gi')
    output=$(echo "$output" | sed -E 's/(PASSWORD|PASSWD|PWD):[^ ]*/\1:***REDACTED***/g')
    output=$(echo "$output" | sed -E 's/--password[= ][^ ]*/--password=***REDACTED***/gi')

    # Redact SECRET_KEY
    output=$(echo "$output" | sed -E 's/(SECRET_KEY|secret_key)[= ][^ ]*/\1=***REDACTED***/g')

    # Redact database connection strings
    output=$(echo "$output" | sed -E 's/(postgresql:\/\/[^:]+:)[^@]+(@)/\1***REDACTED***\2/g')

    echo "$output"
}

# Execute command and log output
# Usage: log_command "description" command arg1 arg2 ...
log_command() {
    local description="$1"
    shift
    local command=("$@")

    log_info "Executing: $description"
    log_debug "Command: ${command[*]}"

    # Execute command and capture output
    local output
    local exit_code

    output=$("${command[@]}" 2>&1)
    exit_code=$?

    # Sanitize output
    output=$(sanitize_log_output "$output")

    if [[ $exit_code -eq 0 ]]; then
        log_debug "Command succeeded"
        if [[ -n "$output" ]]; then
            log_debug "Output: $output"
        fi
    else
        log_error "Command failed with exit code $exit_code"
        if [[ -n "$output" ]]; then
            log_error "Output: $output"
        fi
    fi

    return $exit_code
}

# Execute command silently (only log on error)
log_command_silent() {
    local description="$1"
    shift
    local command=("$@")

    log_debug "Executing (silent): $description"

    local output
    local exit_code

    output=$("${command[@]}" 2>&1)
    exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        output=$(sanitize_log_output "$output")
        log_error "Command failed: $description (exit code $exit_code)"
        if [[ -n "$output" ]]; then
            log_error "Output: $output"
        fi
    fi

    return $exit_code
}

# =============================================================================
# LOG FILE MANAGEMENT
# =============================================================================

# Initialize logging
init_logging() {
    local log_dir
    log_dir=$(dirname "$LOG_FILE")

    # Create log directory if needed
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" 2>/dev/null || {
            echo "ERROR: Cannot create log directory: $log_dir" >&2
            return 1
        }
    fi

    # Create log file if doesn't exist
    if [[ ! -f "$LOG_FILE" ]]; then
        touch "$LOG_FILE" 2>/dev/null || {
            echo "ERROR: Cannot create log file: $LOG_FILE" >&2
            return 1
        }
    fi

    # Set log file permissions (640 - readable by root and log group)
    chmod 640 "$LOG_FILE" 2>/dev/null

    # Log session start
    log_info "=========================================="
    log_info "NetBox Offline Installer - Session Start"
    log_info "Version: ${INSTALLER_VERSION:-unknown}"
    log_info "User: $(whoami)"
    log_info "Hostname: $(hostname)"
    log_info "Working Directory: $(pwd)"
    log_info "Log Level: $LOG_LEVEL"
    log_info "=========================================="

    return 0
}

# Rotate log file if it exceeds threshold
rotate_log() {
    if [[ ! -f "$LOG_FILE" ]]; then
        return 0
    fi

    # Get current file size
    local current_size
    if [[ -f /proc/version ]]; then
        # Linux
        current_size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
    else
        # BSD/macOS fallback
        current_size=$(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)
    fi

    # Check if rotation needed
    if [[ $current_size -gt $LOG_ROTATION_THRESHOLD ]]; then
        log_info "Rotating log file (size: $current_size bytes)"

        local timestamp
        timestamp=$(date '+%Y%m%d-%H%M%S')
        local rotated_log="${LOG_FILE}.${timestamp}"

        # Move current log to rotated name
        mv "$LOG_FILE" "$rotated_log"

        # Compress rotated log
        gzip "$rotated_log" &

        # Create new log file
        touch "$LOG_FILE"
        chmod 640 "$LOG_FILE"

        log_info "Log rotated to: ${rotated_log}.gz"
    fi
}

# Clean up old rotated logs (keep last 10)
cleanup_old_logs() {
    local log_dir
    log_dir=$(dirname "$LOG_FILE")
    local log_basename
    log_basename=$(basename "$LOG_FILE")

    # Find and remove old rotated logs (keep last 10)
    find "$log_dir" -name "${log_basename}.*.gz" -type f | \
        sort -r | \
        tail -n +11 | \
        xargs -r rm -f 2>/dev/null

    log_debug "Cleaned up old log files"
}

# =============================================================================
# SECTION LOGGING
# =============================================================================

# Log section header
log_section() {
    local section_title="$1"
    local separator="======================================"

    log_info ""
    log_info "$separator"
    log_info "$section_title"
    log_info "$separator"
}

# Log subsection header
log_subsection() {
    local subsection_title="$1"
    local separator="--------------------------------------"

    log_info ""
    log_info "$subsection_title"
    log_info "$separator"
}

# =============================================================================
# PROGRESS LOGGING
# =============================================================================

# Log progress with percentage
log_progress() {
    local current="$1"
    local total="$2"
    local description="$3"

    local percentage=$((current * 100 / total))
    log_info "Progress: ${percentage}% (${current}/${total}) - $description"
}

# =============================================================================
# VISUAL PROGRESS INDICATORS
# =============================================================================

# Global variables for spinner
SPINNER_PID=""
SPINNER_MESSAGE=""

# Start a spinner animation
# Usage: start_spinner "Loading message"
start_spinner() {
    local message="$1"
    SPINNER_MESSAGE="$message"

    # Spinner animation function
    {
        local spinner_chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
        local i=0

        # Hide cursor
        tput civis 2>/dev/null || true

        while true; do
            local char="${spinner_chars:i++%${#spinner_chars}:1}"
            printf "\r\033[K\033[0;36m[%s]\033[0m %s" "$char" "$SPINNER_MESSAGE" >&2
            sleep 0.1
        done
    } &

    SPINNER_PID=$!

    # Disable job control messages
    disown $SPINNER_PID 2>/dev/null || true
}

# Stop the spinner animation
# Usage: stop_spinner [exit_code]
stop_spinner() {
    local exit_code="${1:-0}"

    if [[ -n "$SPINNER_PID" ]] && kill -0 "$SPINNER_PID" 2>/dev/null; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
    fi

    # Clear the spinner line
    printf "\r\033[K" >&2

    # Show cursor
    tput cnorm 2>/dev/null || true

    # Display completion status
    if [[ $exit_code -eq 0 ]]; then
        echo -e "\r\033[K\033[0;32m[✓]\033[0m $SPINNER_MESSAGE" >&2
    else
        echo -e "\r\033[K\033[0;31m[✗]\033[0m $SPINNER_MESSAGE" >&2
    fi

    SPINNER_PID=""
    SPINNER_MESSAGE=""
}

# Progress bar display
# Usage: show_progress_bar current total message
show_progress_bar() {
    local current="$1"
    local total="$2"
    local message="$3"

    local percentage=$((current * 100 / total))
    local filled=$((percentage / 2))  # 50 char width
    local empty=$((50 - filled))

    # Build progress bar
    local bar=""
    for ((i=0; i<filled; i++)); do
        bar+="█"
    done
    for ((i=0; i<empty; i++)); do
        bar+="░"
    done

    # Display progress bar
    printf "\r\033[K\033[0;36m[%s]\033[0m %3d%% %s" "$bar" "$percentage" "$message" >&2

    # New line on completion
    if [[ $current -eq $total ]]; then
        echo >&2
    fi
}

# Log step completion
log_step() {
    local step_number="$1"
    local step_description="$2"

    log_info "Step ${step_number}: $step_description"
}

# =============================================================================
# SUMMARY LOGGING
# =============================================================================

# Log success summary
log_success_summary() {
    local operation="$1"

    log_section "SUCCESS: $operation"
    log_info "Operation completed successfully"
    log_info "Timestamp: $(get_timestamp)"
}

# Log failure summary
log_failure_summary() {
    local operation="$1"
    local error_message="$2"

    log_section "FAILURE: $operation"
    log_error "Operation failed: $error_message"
    log_error "Timestamp: $(get_timestamp)"
    log_error "Check log file for details: $LOG_FILE"
}

# =============================================================================
# SPECIAL PURPOSE LOGGING
# =============================================================================

# Log security event
log_security() {
    local event="$1"
    log_message INFO "SECURITY: $event"
}

# Log audit event
log_audit() {
    local event="$1"
    log_message INFO "AUDIT: $event"
}

# Log configuration change
log_config_change() {
    local setting="$1"
    local old_value="$2"
    local new_value="$3"

    # Sanitize values
    old_value=$(sanitize_log_output "$old_value")
    new_value=$(sanitize_log_output "$new_value")

    log_audit "Configuration changed: $setting (was: $old_value, now: $new_value)"
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Auto-initialize logging when sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Script is being sourced, initialize logging
    init_logging
fi

# End of logging.sh
