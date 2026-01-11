#!/bin/bash
#
# NetBox Offline Installer - Credential Management
# Version: 0.0.1
# Description: Secure password generation, validation, and credential handling
#
# Created by: Kismet Agbasi (KismetG17@gmail.com)
# AI Collaborator: Claude Code (integrated with VS Code)
# Date Created: 12/27/2025
# Last Updated: 01/11/2026
#

# =============================================================================
# PASSWORD GENERATION
# =============================================================================

# Generate cryptographically strong password
# Usage: generate_strong_password [length] [character_set]
generate_strong_password() {
    local length="${1:-32}"
    local char_set="${2:-alphanumeric_special}"

    local password

    case "$char_set" in
        alphanumeric)
            # A-Z, a-z, 0-9
            password=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length")
            ;;
        alphanumeric_special)
            # A-Z, a-z, 0-9, and safe special characters
            password=$(tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' < /dev/urandom | head -c "$length")
            ;;
        special_safe)
            # Only safe special characters (no quotes or backslashes)
            password=$(tr -dc 'A-Za-z0-9!@#$%^&*()_+-=[]{}:;,.?' < /dev/urandom | head -c "$length")
            ;;
        *)
            log_error "Invalid character set: $char_set"
            return 1
            ;;
    esac

    # Validate that password meets minimum requirements
    if ! validate_password_strength "$password"; then
        # Retry if generated password doesn't meet requirements
        generate_strong_password "$length" "$char_set"
        return $?
    fi

    echo "$password"
}

# Generate Django SECRET_KEY
# Uses Python's secrets module for cryptographic strength
generate_secret_key() {
    local length="${1:-50}"

    # Try using Python's secrets module (most secure)
    if command -v python3 &>/dev/null; then
        python3 -c "from secrets import token_urlsafe; print(token_urlsafe(${length}))" 2>/dev/null && return 0
    fi

    # Fallback to urandom-based generation
    tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' < /dev/urandom | head -c "$length"
}

# =============================================================================
# PASSWORD VALIDATION
# =============================================================================

# Validate password strength
# Returns 0 if password meets requirements, 1 otherwise
validate_password_strength() {
    local password="$1"
    local min_length="${2:-12}"

    # Check minimum length
    if [[ ${#password} -lt $min_length ]]; then
        log_debug "Password too short: ${#password} < $min_length"
        return 1
    fi

    # Check for uppercase letter
    if [[ ! "$password" =~ [A-Z] ]]; then
        log_debug "Password missing uppercase letter"
        return 1
    fi

    # Check for lowercase letter
    if [[ ! "$password" =~ [a-z] ]]; then
        log_debug "Password missing lowercase letter"
        return 1
    fi

    # Check for digit
    if [[ ! "$password" =~ [0-9] ]]; then
        log_debug "Password missing digit"
        return 1
    fi

    # Check for special character
    if [[ ! "$password" =~ [^A-Za-z0-9] ]]; then
        log_debug "Password missing special character"
        return 1
    fi

    # Password meets all requirements
    return 0
}

# Display password requirements
display_password_requirements() {
    cat <<EOF
Password Requirements:
- Minimum length: 12 characters
- At least one uppercase letter (A-Z)
- At least one lowercase letter (a-z)
- At least one digit (0-9)
- At least one special character (!@#$%^&*()_+-=, etc.)
EOF
}

# =============================================================================
# SECURE PASSWORD PROMPTING
# =============================================================================

# Prompt for password with confirmation
# Usage: prompt_password "prompt message" [min_length]
prompt_password() {
    local prompt="$1"
    local min_length="${2:-12}"
    local password
    local password_confirm

    while true; do
        # Read password with asterisk feedback and backspace support
        password=""
        echo -n "$prompt: " >&2
        while IFS= read -r -s -n1 char; do
            if [[ $char == $'\0' ]]; then
                break
            fi
            if [[ $char == $'\177' ]]; then
                # Backspace
                if [[ -n "$password" ]]; then
                    password="${password%?}"
                    echo -ne "\b \b" >&2
                fi
            else
                password+="$char"
                echo -n "*" >&2
            fi
        done
        echo >&2

        # Check if empty
        if [[ -z "$password" ]]; then
            log_warn "Password cannot be empty"
            continue
        fi

        # Validate password strength
        if ! validate_password_strength "$password" "$min_length"; then
            log_warn "Password does not meet complexity requirements"
            echo
            display_password_requirements
            echo
            continue
        fi

        # Confirm password with asterisk feedback and backspace support
        password_confirm=""
        echo -n "Confirm password: " >&2
        while IFS= read -r -s -n1 char; do
            if [[ $char == $'\0' ]]; then
                break
            fi
            if [[ $char == $'\177' ]]; then
                # Backspace
                if [[ -n "$password_confirm" ]]; then
                    password_confirm="${password_confirm%?}"
                    echo -ne "\b \b" >&2
                fi
            else
                password_confirm+="$char"
                echo -n "*" >&2
            fi
        done
        echo >&2

        if [[ "$password" == "$password_confirm" ]]; then
            echo "$password"
            return 0
        else
            log_warn "Passwords do not match, please try again"
            echo
        fi
    done
}

# Prompt for password with option to generate
# Usage: prompt_or_generate_password "prompt message" [default_action]
prompt_or_generate_password() {
    local prompt="$1"
    local default_action="${2:-generate}"  # generate or prompt

    local action
    if [[ "$default_action" == "generate" ]]; then
        read -r -p "$prompt [Generate/Enter]: " action
        action="${action:-generate}"
    else
        read -r -p "$prompt [Enter/Generate]: " action
        action="${action:-enter}"
    fi

    case "${action,,}" in
        g|gen|generate)
            local password
            password=$(generate_strong_password 32)
            log_info "Generated strong password"
            echo "$password"
            return 0
            ;;
        e|enter|prompt)
            prompt_password "Enter password"
            return $?
            ;;
        *)
            log_error "Invalid choice: $action"
            prompt_or_generate_password "$prompt" "$default_action"
            return $?
            ;;
    esac
}

# =============================================================================
# CREDENTIAL STORAGE (IN-MEMORY ONLY)
# =============================================================================

# Store credential securely in memory (environment variable)
# Never persisted to disk
store_credential() {
    local key="$1"
    local value="$2"

    # Store in environment (will be cleared on exit)
    export "$key=$value"

    log_security "Credential stored in memory: $key"
}

# Retrieve credential from memory
get_credential() {
    local key="$1"

    # Retrieve from environment
    echo "${!key}"
}

# Clear credential from memory
clear_credential() {
    local key="$1"

    unset "$key"
    log_security "Credential cleared from memory: $key"
}

# Clear all stored credentials
clear_all_credentials() {
    log_debug "Clearing all stored credentials"

    # List of credential variables to clear
    local credentials=(
        "DB_PASSWORD"
        "DB_ADMIN_PASSWORD"
        "SUPERUSER_PASSWORD"
        "SECRET_KEY"
        "REDIS_PASSWORD"
    )

    for cred in "${credentials[@]}"; do
        if [[ -n "${!cred}" ]]; then
            unset "$cred"
        fi
    done

    log_security "All credentials cleared from memory"
}

# =============================================================================
# CONFIGURATION TOKEN PROCESSING
# =============================================================================

# Process configuration tokens (<generate>, <prompt>)
# Usage: process_config_token "variable_name" "token_value"
process_config_token() {
    local var_name="$1"
    local token_value="$2"

    case "$token_value" in
        "<generate>")
            log_info "Generating value for $var_name"
            case "$var_name" in
                SECRET_KEY)
                    generate_secret_key
                    ;;
                *PASSWORD*)
                    generate_strong_password 32
                    ;;
                *)
                    generate_strong_password 32
                    ;;
            esac
            ;;
        "<prompt>")
            log_info "Prompting for $var_name"
            # Convert variable name to human-readable prompt
            local prompt_text
            case "$var_name" in
                SUPERUSER_PASSWORD)
                    prompt_text="NetBox superuser password"
                    ;;
                DB_PASSWORD)
                    prompt_text="database password"
                    ;;
                DB_ADMIN_PASSWORD)
                    prompt_text="database admin password"
                    ;;
                *)
                    # Fallback: convert variable name to lowercase with spaces
                    prompt_text=$(echo "$var_name" | tr '_' ' ' | tr '[:upper:]' '[:lower:]')
                    ;;
            esac
            prompt_password "Enter $prompt_text"
            ;;
        *)
            # Return value as-is (literal value or already processed)
            echo "$token_value"
            ;;
    esac
}

# =============================================================================
# DATABASE CREDENTIAL MANAGEMENT
# =============================================================================

# Generate database password
generate_db_password() {
    local length="${1:-32}"

    log_security "Generating database password"
    generate_strong_password "$length" "special_safe"
}

# Prompt for database password
prompt_db_password() {
    local db_name="${1:-database}"

    log_security "Prompting for database password: $db_name"
    prompt_password "Enter password for $db_name" 16
}

# =============================================================================
# PASSWORD DISPLAY (FOR AUTO-GENERATED PASSWORDS)
# =============================================================================

# Display generated password to user (one-time display)
display_generated_password() {
    local purpose="$1"
    local password="$2"
    local save_instructions="${3:-true}"

    cat <<EOF

================================================================================
IMPORTANT: Generated Password for $purpose
================================================================================
Password: $password

SAVE THIS PASSWORD NOW! It will not be displayed again.
EOF

    if [[ "$save_instructions" == "true" ]]; then
        cat <<EOF

Recommended: Copy this password to a secure password manager.
This password has NOT been saved to disk for security reasons.

EOF
    fi

    cat <<EOF
================================================================================

EOF

    # Wait for user acknowledgment
    read -r -p "Press Enter to continue after saving the password..."
    echo
}

# =============================================================================
# POSTGRESQL CONNECTION STRING BUILDING
# =============================================================================

# Build PostgreSQL connection string (with password masked in logs)
build_pg_connection_string() {
    local db_host="$1"
    local db_port="$2"
    local db_name="$3"
    local db_user="$4"
    local db_password="$5"

    # Format: postgresql://user:password@host:port/database
    echo "postgresql://${db_user}:${db_password}@${db_host}:${db_port}/${db_name}"
}

# Build PostgreSQL connection string for psql command
build_psql_connection() {
    local db_host="$1"
    local db_port="$2"
    local db_name="$3"
    local db_user="$4"
    local db_password="$5"

    # Export PGPASSWORD for psql (will be cleared after use)
    export PGPASSWORD="$db_password"

    # Return psql command arguments
    echo "-h $db_host -p $db_port -U $db_user -d $db_name"
}

# Clear PostgreSQL password from environment
clear_pg_password() {
    unset PGPASSWORD
}

# =============================================================================
# CREDENTIAL VALIDATION
# =============================================================================

# Validate that all required credentials are set
validate_required_credentials() {
    local required_creds=("$@")
    local missing_creds=()

    for cred in "${required_creds[@]}"; do
        if [[ -z "${!cred}" ]]; then
            missing_creds+=("$cred")
        fi
    done

    if [[ ${#missing_creds[@]} -gt 0 ]]; then
        log_error "Missing required credentials:"
        for cred in "${missing_creds[@]}"; do
            log_error "  - $cred"
        done
        return 1
    fi

    log_info "All required credentials validated"
    return 0
}

# =============================================================================
# SECURITY AUDIT FUNCTIONS
# =============================================================================

# Check for plaintext passwords in files
check_plaintext_passwords() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        return 0
    fi

    # Look for common password patterns (excluding tokens)
    if grep -E '(PASSWORD|PASSWD|SECRET)[^=]*=[^<]' "$file" | grep -v '<generate>' | grep -v '<prompt>' | grep -qv '^[[:space:]]*#'; then
        log_warn "Potential plaintext password found in $file"
        log_warn "Ensure all passwords use <generate> or <prompt> tokens"
        return 1
    fi

    return 0
}

# Audit configuration file for security issues
audit_config_security() {
    local config_file="$1"

    log_security "Auditing configuration file: $config_file"

    local issues_found=0

    # Check for plaintext passwords
    if ! check_plaintext_passwords "$config_file"; then
        ((issues_found++))
    fi

    # Check file permissions
    if [[ -f "$config_file" ]]; then
        local perms
        perms=$(stat -c %a "$config_file" 2>/dev/null || stat -f %OLp "$config_file" 2>/dev/null)

        if [[ "$perms" != "600" && "$perms" != "640" ]]; then
            log_warn "Configuration file has insecure permissions: $perms"
            log_warn "Recommended: 640 (readable by owner and group only)"
            ((issues_found++))
        fi
    fi

    if [[ $issues_found -gt 0 ]]; then
        log_warn "Security audit found $issues_found issue(s) in $config_file"
        return 1
    fi

    log_info "Configuration file passed security audit"
    return 0
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Register cleanup handler for credentials
register_credential_cleanup() {
    # Add to existing EXIT trap
    trap 'clear_all_credentials' EXIT

    log_debug "Credential cleanup handler registered"
}

# Auto-initialize when sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    register_credential_cleanup
fi

# End of credentials.sh
