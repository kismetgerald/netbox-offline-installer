#!/bin/bash
#
# NetBox Offline Installer - Installation Module
# Version: 0.0.1
# Description: Offline installation orchestration on air-gapped machine
#
# Created by: Kismet Agbasi (KismetG17@gmail.com)
# AI Collaborator: Claude Code (integrated with VS Code)
# Date Created: 12/27/2025
# Last Updated: 01/11/2026
#
# This module runs on an offline RHEL 9/10 system and:
# - Validates offline installation package
# - Installs system dependencies from RPMs
# - Configures PostgreSQL (local or remote)
# - Installs NetBox from offline wheels
# - Configures web server (Nginx)
# - Applies security hardening
# - Creates initial backup
#

# =============================================================================
# INSTALLATION CONFIGURATION
# =============================================================================

# Default installation path
DEFAULT_INSTALL_PATH="/opt/netbox"

# PostgreSQL configuration (detected dynamically)
POSTGRESQL_SERVICE=""
POSTGRESQL_DATA_DIR=""

# Systemd service names
NETBOX_SERVICE="netbox"
NETBOX_RQ_SERVICE="netbox-rq"

# =============================================================================
# PACKAGE VALIDATION
# =============================================================================

# Validate offline package structure
validate_package_structure() {
    local package_dir="$1"

    log_function_entry

    log_info "Validating offline package structure..."

    # Check required directories
    local required_dirs=(
        "rpms"
        "wheels"
        "netbox-source"
        "lib"
        "config"
        "templates"
    )

    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$package_dir/$dir" ]]; then
            log_error "Missing required directory: $dir"
            log_function_exit 1
            return 1
        fi
    done

    # Check for manifest
    if [[ ! -f "$package_dir/manifest.txt" ]]; then
        log_warn "Manifest file not found (non-critical)"
    fi

    # Check for checksums
    if [[ ! -f "$package_dir/checksums.txt" ]]; then
        log_warn "Checksums file not found - integrity verification skipped"
    else
        # Verify package integrity
        log_info "Verifying package integrity..."
        if ! verify_package_integrity "$package_dir"; then
            log_error "Package integrity verification failed"
            log_function_exit 1
            return 1
        fi
    fi

    log_info "Package structure validation passed"
    log_function_exit 0
    return 0
}

# Extract NetBox version from package
get_package_netbox_version() {
    local package_dir="$1"

    log_function_entry

    # Find NetBox source tarball
    local netbox_tarball
    netbox_tarball=$(find "$package_dir/netbox-source" -name "netbox-*.tar.gz" -type f | head -1)

    if [[ -z "$netbox_tarball" ]]; then
        log_error "NetBox source tarball not found in package"
        log_function_exit 1
        return 1
    fi

    # Extract version from filename (netbox-X.Y.Z.tar.gz)
    local version
    version=$(basename "$netbox_tarball" | sed -E 's/netbox-([0-9]+\.[0-9]+\.[0-9]+)\.tar\.gz/\1/')

    if [[ -z "$version" ]]; then
        log_error "Could not extract version from tarball name"
        log_function_exit 1
        return 1
    fi

    echo "$version"
    log_function_exit 0
    return 0
}

# =============================================================================
# RPM INSTALLATION
# =============================================================================

# Install RPM packages from offline package
install_rpm_packages() {
    local package_dir="$1"

    log_function_entry
    log_section "Installing System Dependencies"

    local rpms_dir="${package_dir}/rpms"

    # Count RPMs
    local rpm_count
    rpm_count=$(find "$rpms_dir" -name "*.rpm" | wc -l)

    if [[ $rpm_count -eq 0 ]]; then
        log_error "No RPM packages found in $rpms_dir"
        log_function_exit 1
        return 1
    fi

    log_info "Installing $rpm_count RPM packages..."

    # Start spinner for long-running operation
    start_spinner "Installing RPM packages (this may take several minutes)..."

    # Install all RPMs using dnf localinstall
    # --nogpgcheck: Skip GPG check (offline package)
    # --skip-broken: Skip packages with dependency issues
    # Redirect all output to log file to avoid subscription manager messages on console
    if dnf localinstall -y --nogpgcheck "$rpms_dir"/*.rpm >> "$LOG_FILE" 2>&1; then
        stop_spinner 0
        log_info "RPM packages installed successfully"
        log_function_exit 0
        return 0
    else
        stop_spinner 1
        log_error "Failed to install RPM packages"
        log_error "Check log file for details: $LOG_FILE"
        log_function_exit 1
        return 1
    fi
}

# =============================================================================
# POSTGRESQL CONFIGURATION (LOCAL MODE)
# =============================================================================

# Detect PostgreSQL version and set service/data paths
detect_postgresql_version() {
    log_function_entry

    # Try to find postgresql-server package
    local pg_version

    # Check for different PostgreSQL versions (16, 15, 14, 13)
    for ver in 16 15 14 13; do
        if rpm -q "postgresql${ver}-server" &>/dev/null || rpm -q "postgresql-server" &>/dev/null; then
            # For versioned packages (postgresql16-server)
            if rpm -q "postgresql${ver}-server" &>/dev/null; then
                pg_version="$ver"
                POSTGRESQL_SERVICE="postgresql-${ver}"
                POSTGRESQL_DATA_DIR="/var/lib/pgsql/${ver}/data"
                break
            # For unversioned package (postgresql-server) - get version from rpm
            elif rpm -q "postgresql-server" &>/dev/null; then
                # Get version from rpm query
                local pkg_version
                pkg_version=$(rpm -q --queryformat '%{VERSION}' postgresql-server | cut -d. -f1)
                pg_version="$pkg_version"
                POSTGRESQL_SERVICE="postgresql"
                POSTGRESQL_DATA_DIR="/var/lib/pgsql/data"
                break
            fi
        fi
    done

    if [[ -z "$pg_version" ]]; then
        log_error "PostgreSQL server package not found"
        log_error "Expected: postgresql-server or postgresql13-server (or higher)"
        log_function_exit 1
        return 1
    fi

    log_info "Detected PostgreSQL version: $pg_version"
    log_info "Service name: $POSTGRESQL_SERVICE"
    log_info "Data directory: $POSTGRESQL_DATA_DIR"

    log_function_exit 0
    return 0
}

# Initialize PostgreSQL database
initialize_postgresql() {
    log_function_entry
    log_subsection "Initializing PostgreSQL"

    # Detect PostgreSQL version first
    if ! detect_postgresql_version; then
        log_function_exit 1
        return 1
    fi

    # Check if already initialized
    if [[ -f "$POSTGRESQL_DATA_DIR/PG_VERSION" ]]; then
        log_info "PostgreSQL already initialized"
        log_function_exit 0
        return 0
    fi

    # Initialize database
    log_info "Initializing PostgreSQL database cluster..."

    # Use different initialization commands based on service name
    if [[ "$POSTGRESQL_SERVICE" == "postgresql" ]]; then
        # RHEL 9 with postgresql-server (unversioned)
        if postgresql-setup --initdb --unit postgresql >> "$LOG_FILE" 2>&1; then
            log_info "PostgreSQL initialized successfully"
            log_function_exit 0
            return 0
        fi
    else
        # RHEL with versioned package (postgresql-16, etc.)
        if postgresql-setup --initdb --unit "$POSTGRESQL_SERVICE" >> "$LOG_FILE" 2>&1; then
            log_info "PostgreSQL initialized successfully"
            log_function_exit 0
            return 0
        fi
    fi

    log_error "Failed to initialize PostgreSQL"
    log_error "Check $LOG_FILE for details"
    log_function_exit 1
    return 1
}

# Configure PostgreSQL for local connections
configure_postgresql_local() {
    log_function_entry
    log_subsection "Configuring PostgreSQL"

    local pg_hba_conf="${POSTGRESQL_DATA_DIR}/pg_hba.conf"

    if [[ ! -f "$pg_hba_conf" ]]; then
        log_error "PostgreSQL configuration file not found: $pg_hba_conf"
        log_function_exit 1
        return 1
    fi

    log_info "Configuring pg_hba.conf for local connections..."

    # Backup original pg_hba.conf
    cp "$pg_hba_conf" "${pg_hba_conf}.bak"

    # Add NetBox database connection rule (md5 authentication for local connections)
    # This allows the netbox user to connect with password
    if ! grep -q "^host.*netbox.*netbox.*md5" "$pg_hba_conf"; then
        # Insert before the default local rule
        sed -i '/^host.*all.*all.*127.0.0.1/i host    netbox          netbox          127.0.0.1/32            md5' "$pg_hba_conf"
        log_info "Added NetBox connection rule to pg_hba.conf"
    fi

    log_function_exit 0
    return 0
}

# Start and enable PostgreSQL service
start_postgresql_service() {
    log_function_entry
    log_subsection "Starting PostgreSQL Service"

    # Enable service
    if systemctl enable "$POSTGRESQL_SERVICE" >> "$LOG_FILE" 2>&1; then
        log_info "PostgreSQL service enabled"
    else
        log_warn "Failed to enable PostgreSQL service"
    fi

    # Start service
    if systemctl start "$POSTGRESQL_SERVICE" 2>&1 | tee -a "$LOG_FILE"; then
        log_info "PostgreSQL service started"
    else
        log_error "Failed to start PostgreSQL service"
        log_function_exit 1
        return 1
    fi

    # Wait for PostgreSQL to be ready
    local retry_count=0
    local max_retries=30

    while [[ $retry_count -lt $max_retries ]]; do
        if systemctl is-active --quiet "$POSTGRESQL_SERVICE"; then
            log_info "PostgreSQL is active"
            log_function_exit 0
            return 0
        fi

        ((retry_count++))
        log_debug "Waiting for PostgreSQL to start... ($retry_count/$max_retries)"
        sleep 1
    done

    log_error "PostgreSQL failed to start within timeout"
    log_function_exit 1
    return 1
}

# Create NetBox database and user (local mode)
create_netbox_database_local() {
    local db_name="$1"
    local db_user="$2"
    local db_password="$3"

    log_function_entry
    log_subsection "Creating NetBox Database"

    log_info "Creating database: $db_name"
    log_info "Creating user: $db_user"

    # Create database
    if sudo -u postgres psql -c "CREATE DATABASE ${db_name};" >> "$LOG_FILE" 2>&1; then
        log_info "Database created: $db_name"
    else
        # Database might already exist
        if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$db_name"; then
            log_warn "Database already exists: $db_name"
        else
            log_error "Failed to create database: $db_name"
            log_function_exit 1
            return 1
        fi
    fi

    # Create user with password
    # Note: Redirect output to log without password redaction (psql doesn't echo passwords)
    if sudo -u postgres psql -c "CREATE USER ${db_user} WITH PASSWORD '${db_password}';" >> "$LOG_FILE" 2>&1; then
        log_info "User created: $db_user"
    else
        # User might already exist
        if sudo -u postgres psql -c "\du" | grep -qw "$db_user"; then
            log_warn "User already exists: $db_user"
            # Update password
            sudo -u postgres psql -c "ALTER USER ${db_user} WITH PASSWORD '${db_password}';" &>/dev/null
            log_info "Updated password for existing user: $db_user"
        else
            log_error "Failed to create user: $db_user"
            log_function_exit 1
            return 1
        fi
    fi

    # Grant privileges
    log_info "Granting database ownership to user..."

    if sudo -u postgres psql -c "ALTER DATABASE ${db_name} OWNER TO ${db_user};" >> "$LOG_FILE" 2>&1; then
        log_info "Database ownership granted"
    else
        log_error "Failed to grant database ownership"
        log_function_exit 1
        return 1
    fi

    # Grant additional privileges
    sudo -u postgres psql -d "$db_name" -c "GRANT ALL PRIVILEGES ON DATABASE ${db_name} TO ${db_user};" &>/dev/null

    log_security "PostgreSQL database and user created for NetBox"
    log_function_exit 0
    return 0
}

# =============================================================================
# POSTGRESQL CONFIGURATION (REMOTE MODE)
# =============================================================================

# Test connection to remote PostgreSQL server
test_remote_postgresql_connection() {
    local db_host="$1"
    local db_port="$2"
    local db_user="$3"
    local db_password="$4"

    log_function_entry

    log_info "Testing connection to remote PostgreSQL server..."
    log_info "Host: $db_host:$db_port"

    # Set PGPASSWORD for psql
    export PGPASSWORD="$db_password"

    # Test connection
    if psql -h "$db_host" -p "$db_port" -U "$db_user" -d postgres -c '\l' &>/dev/null; then
        log_info "Connection successful"
        unset PGPASSWORD
        log_function_exit 0
        return 0
    else
        log_error "Failed to connect to remote PostgreSQL server"
        log_error "Check host, port, credentials, and network connectivity"
        unset PGPASSWORD
        log_function_exit 1
        return 1
    fi
}

# Verify remote PostgreSQL version
verify_remote_postgresql_version() {
    local db_host="$1"
    local db_port="$2"
    local db_user="$3"
    local db_password="$4"

    log_function_entry

    export PGPASSWORD="$db_password"

    # Get PostgreSQL version
    local pg_version
    pg_version=$(psql -h "$db_host" -p "$db_port" -U "$db_user" -d postgres -t -c "SHOW server_version;" 2>/dev/null | awk '{print $1}')

    unset PGPASSWORD

    if [[ -z "$pg_version" ]]; then
        log_error "Could not determine remote PostgreSQL version"
        log_function_exit 1
        return 1
    fi

    log_info "Remote PostgreSQL version: $pg_version"

    # Check minimum version (14.0)
    if version_compare "$pg_version" ">=" "$MIN_POSTGRESQL_VERSION"; then
        log_info "PostgreSQL version meets minimum requirement (${MIN_POSTGRESQL_VERSION}+)"
        log_function_exit 0
        return 0
    else
        log_error "PostgreSQL version too old: $pg_version < $MIN_POSTGRESQL_VERSION"
        log_function_exit 1
        return 1
    fi
}

# Create NetBox database on remote PostgreSQL server
create_netbox_database_remote() {
    local db_host="$1"
    local db_port="$2"
    local admin_user="$3"
    local admin_password="$4"
    local db_name="$5"
    local db_user="$6"
    local db_password="$7"

    log_function_entry
    log_subsection "Creating NetBox Database (Remote)"

    export PGPASSWORD="$admin_password"

    log_info "Creating database: $db_name"

    # Create database
    if psql -h "$db_host" -p "$db_port" -U "$admin_user" -d postgres \
        -c "CREATE DATABASE ${db_name};" 2>&1 | tee -a "$LOG_FILE"; then
        log_info "Database created: $db_name"
    else
        log_warn "Database creation failed (may already exist)"
    fi

    log_info "Creating user: $db_user"

    # Create user
    if psql -h "$db_host" -p "$db_port" -U "$admin_user" -d postgres \
        -c "CREATE USER ${db_user} WITH PASSWORD '${db_password}';" 2>&1 | \
        sed "s/${db_password}/***REDACTED***/g" | tee -a "$LOG_FILE"; then
        log_info "User created: $db_user"
    else
        log_warn "User creation failed (may already exist)"
        # Update password
        psql -h "$db_host" -p "$db_port" -U "$admin_user" -d postgres \
            -c "ALTER USER ${db_user} WITH PASSWORD '${db_password}';" &>/dev/null
        log_info "Updated password for existing user"
    fi

    # Grant privileges
    log_info "Granting database ownership..."

    psql -h "$db_host" -p "$db_port" -U "$admin_user" -d postgres \
        -c "ALTER DATABASE ${db_name} OWNER TO ${db_user};" 2>&1 | tee -a "$LOG_FILE"

    psql -h "$db_host" -p "$db_port" -U "$admin_user" -d "$db_name" \
        -c "GRANT ALL PRIVILEGES ON DATABASE ${db_name} TO ${db_user};" &>/dev/null

    unset PGPASSWORD

    log_security "Remote PostgreSQL database and user created for NetBox"
    log_function_exit 0
    return 0
}

# =============================================================================
# REDIS CONFIGURATION
# =============================================================================

# Start and enable Redis service
start_redis_service() {
    log_function_entry
    log_subsection "Starting Redis Service"

    # Enable service
    if systemctl enable redis >> "$LOG_FILE" 2>&1; then
        log_info "Redis service enabled"
    else
        log_warn "Failed to enable Redis service"
    fi

    # Start service
    if systemctl start redis 2>&1 | tee -a "$LOG_FILE"; then
        log_info "Redis service started"
        log_function_exit 0
        return 0
    else
        log_error "Failed to start Redis service"
        log_function_exit 1
        return 1
    fi
}

# =============================================================================
# NETBOX INSTALLATION
# =============================================================================

# Extract NetBox source to installation directory
extract_netbox_source() {
    local package_dir="$1"
    local install_path="$2"

    log_function_entry
    log_subsection "Extracting NetBox Source"

    # Find NetBox tarball
    local netbox_tarball
    netbox_tarball=$(find "$package_dir/netbox-source" -name "netbox-*.tar.gz" -type f | head -1)

    if [[ -z "$netbox_tarball" ]]; then
        log_error "NetBox source tarball not found"
        log_function_exit 1
        return 1
    fi

    log_info "Extracting NetBox source..."
    log_info "From: $netbox_tarball"
    log_info "To: $install_path"

    # Create installation directory
    if ! mkdir -p "$install_path"; then
        log_error "Failed to create installation directory: $install_path"
        log_function_exit 1
        return 1
    fi

    # Extract tarball
    if tar -xzf "$netbox_tarball" -C "$install_path" --strip-components=1; then
        log_info "NetBox source extracted successfully"
        log_function_exit 0
        return 0
    else
        log_error "Failed to extract NetBox source"
        log_function_exit 1
        return 1
    fi
}

# Create Python virtual environment
create_python_venv() {
    local install_path="$1"
    local required_python_version="${2:-}"  # Optional: specific Python version from manifest (e.g., "3.11")

    log_function_entry
    log_subsection "Creating Python Virtual Environment"

    local venv_path="${install_path}/venv"

    # Detect Python command
    local python_cmd
    if [[ -n "$required_python_version" ]]; then
        # Use specific Python version from manifest
        local pyver="python${required_python_version}"
        if command -v "$pyver" &>/dev/null; then
            python_cmd="$pyver"
            log_info "Using Python version from manifest: $required_python_version"
        else
            log_error "Required Python $required_python_version not found (specified in manifest)"
            log_error "Package was built for Python $required_python_version"
            log_function_exit 1
            return 1
        fi
    else
        # Fallback to auto-detection if no version specified
        if command -v python3.12 &>/dev/null; then
            python_cmd="python3.12"
        elif command -v python3.11 &>/dev/null; then
            python_cmd="python3.11"
        elif command -v python3.10 &>/dev/null; then
            python_cmd="python3.10"
        elif command -v python3 &>/dev/null; then
            python_cmd="python3"
        else
            log_error "No suitable Python 3 installation found"
            log_function_exit 1
            return 1
        fi
    fi

    local python_version
    python_version=$($python_cmd --version | awk '{print $2}')
    log_info "Using Python: $python_cmd (version $python_version)"

    # Create virtual environment
    log_info "Creating virtual environment: $venv_path"

    if $python_cmd -m venv "$venv_path" 2>&1 | tee -a "$LOG_FILE"; then
        log_info "Virtual environment created successfully"

        # Upgrade pip
        log_info "Upgrading pip in virtual environment..."
        "${venv_path}/bin/pip" install --upgrade pip &>/dev/null || \
            log_warn "Failed to upgrade pip"

        log_function_exit 0
        return 0
    else
        log_error "Failed to create virtual environment"
        log_function_exit 1
        return 1
    fi
}

# Install Python dependencies from offline wheels
install_python_dependencies() {
    local package_dir="$1"
    local install_path="$2"

    log_function_entry
    log_subsection "Installing Python Dependencies"

    local wheels_dir="${package_dir}/wheels"
    local venv_path="${install_path}/venv"
    local pip_cmd="${venv_path}/bin/pip"

    # Count wheels
    local wheel_count
    wheel_count=$(find "$wheels_dir" -name "*.whl" | wc -l)

    log_info "Installing $wheel_count Python packages from offline wheels..."
    log_info "This may take several minutes..."

    # Find requirements file in NetBox source
    local requirements_file="${install_path}/requirements.txt"

    if [[ ! -f "$requirements_file" ]]; then
        log_error "requirements.txt not found in NetBox source"
        log_function_exit 1
        return 1
    fi

    # Install from wheels (offline)
    # Note: Send output to log file to avoid cluttering console
    if $pip_cmd install \
        --no-index \
        --find-links="$wheels_dir" \
        -r "$requirements_file" \
        >> "$LOG_FILE" 2>&1; then

        log_info "Python dependencies installed successfully"
        log_function_exit 0
        return 0
    else
        log_error "Failed to install Python dependencies"
        log_error "Check log file for details: $LOG_FILE"
        log_error "Last 20 lines of log:"
        tail -n 20 "$LOG_FILE" | while IFS= read -r line; do
            log_error "  $line"
        done
        log_function_exit 1
        return 1
    fi
}

# =============================================================================
# NETBOX CONFIGURATION
# =============================================================================

# Auto-detect ALLOWED_HOSTS for NetBox
# Returns a space-separated list of hostnames and IP addresses
auto_detect_allowed_hosts() {
    log_function_entry

    local hosts="localhost 127.0.0.1"

    # Get fully qualified domain name
    local fqdn
    fqdn=$(hostname -f 2>/dev/null)
    if [[ -n "$fqdn" ]] && [[ "$fqdn" != "localhost" ]]; then
        hosts="$hosts $fqdn"
        log_info "Detected FQDN: $fqdn"
    fi

    # Get short hostname (if different from FQDN)
    local short_hostname
    short_hostname=$(hostname -s 2>/dev/null)
    if [[ -n "$short_hostname" ]] && [[ "$short_hostname" != "localhost" ]] && [[ "$short_hostname" != "$fqdn" ]]; then
        hosts="$hosts $short_hostname"
        log_info "Detected hostname: $short_hostname"
    fi

    # Get all IP addresses (excluding loopback)
    local ip_addresses
    ip_addresses=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -v '^127\.' | grep -v '^::1' | tr '\n' ' ')
    if [[ -n "$ip_addresses" ]]; then
        hosts="$hosts $ip_addresses"
        log_info "Detected IP addresses: $ip_addresses"
    fi

    # Add wildcard for development/testing (optional - can be removed for production)
    hosts="$hosts *"

    # Remove duplicate entries
    hosts=$(echo "$hosts" | tr ' ' '\n' | sort -u | tr '\n' ' ')

    log_info "ALLOWED_HOSTS: $hosts"
    log_function_exit 0

    echo "$hosts"
}

# Generate NetBox configuration from template
generate_netbox_configuration() {
    local install_path="$1"
    local db_host="$2"
    local db_port="$3"
    local db_name="$4"
    local db_user="$5"
    local db_password="$6"
    local redis_host="$7"
    local redis_port="$8"
    local redis_db="$9"
    local redis_cache_db="${10}"
    local allowed_hosts="${11}"
    local secret_key="${12}"

    log_function_entry
    log_subsection "Generating NetBox Configuration"

    local config_file="${install_path}/netbox/netbox/configuration.py"
    local example_config="${install_path}/netbox/netbox/configuration_example.py"

    # Copy example configuration
    if [[ ! -f "$example_config" ]]; then
        log_error "Configuration example not found: $example_config"
        log_function_exit 1
        return 1
    fi

    cp "$example_config" "$config_file"

    log_info "Configuring NetBox..."

    # Remove the placeholder DATABASES configuration from the example file
    # This prevents duplicate DATABASES blocks
    log_info "Removing placeholder DATABASES configuration..."
    sed -i '/^DATABASES = {/,/^}/d' "$config_file"

    # Configure database settings
    cat >> "$config_file" <<EOF

# =============================================================================
# DATABASE CONFIGURATION (Generated by NetBox Offline Installer)
# =============================================================================

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': '${db_name}',
        'USER': '${db_user}',
        'PASSWORD': '${db_password}',
        'HOST': '${db_host}',
        'PORT': ${db_port},
    }
}

# =============================================================================
# REDIS CONFIGURATION
# =============================================================================

REDIS = {
    'tasks': {
        'HOST': '${redis_host}',
        'PORT': ${redis_port},
        'DATABASE': ${redis_db},
        'SSL': False,
    },
    'caching': {
        'HOST': '${redis_host}',
        'PORT': ${redis_port},
        'DATABASE': ${redis_cache_db},
        'SSL': False,
    },
}

# =============================================================================
# ALLOWED HOSTS
# =============================================================================

ALLOWED_HOSTS = [$(echo "$allowed_hosts" | sed "s/\([^ ]*\)/'\1'/g" | tr ' ' ',')]

# =============================================================================
# SECRET KEY
# =============================================================================

SECRET_KEY = '${secret_key}'

EOF

    # Set secure permissions
    chmod 640 "$config_file"

    log_info "NetBox configuration generated: $config_file"
    log_security "NetBox configuration created with secure permissions (640)"
    log_function_exit 0
    return 0
}

# Run NetBox database migrations
run_netbox_migrations() {
    local install_path="$1"

    log_function_entry
    log_subsection "Running Database Migrations"

    local manage_py="${install_path}/netbox/manage.py"
    local python_cmd="${install_path}/venv/bin/python"

    if [[ ! -f "$manage_py" ]]; then
        log_error "manage.py not found: $manage_py"
        log_function_exit 1
        return 1
    fi

    log_info "Running Django database migrations..."
    log_info "This may take several minutes..."

    # Run migrations and stream output in real-time to both console and log file
    # Create a temporary file to store output and capture exit code
    local temp_output
    temp_output=$(mktemp)
    local exit_code=0

    # Stream output line by line in real-time
    $python_cmd "$manage_py" migrate 2>&1 | while IFS= read -r line; do
        # Display to console through logging framework
        log_info "$line"
        # Append to temp file for exit code check
        echo "$line" >> "$temp_output"
    done

    # Capture exit code from the pipeline
    exit_code=${PIPESTATUS[0]}

    # Clean up temp file
    rm -f "$temp_output"

    if [[ $exit_code -eq 0 ]]; then
        log_info "Database migrations completed successfully"
        log_function_exit 0
        return 0
    else
        log_error "Database migrations failed"
        log_error "Exit code: $exit_code"
        log_function_exit 1
        return 1
    fi
}

# Collect NetBox static files
collect_static_files() {
    local install_path="$1"

    log_function_entry
    log_subsection "Collecting Static Files"

    local manage_py="${install_path}/netbox/manage.py"
    local python_cmd="${install_path}/venv/bin/python"

    log_info "Collecting Django static files..."

    # Run collectstatic and capture output line by line with logging framework
    local collectstatic_output
    local exit_code

    collectstatic_output=$($python_cmd "$manage_py" collectstatic --no-input 2>&1)
    exit_code=$?

    # Log the output line by line
    echo "$collectstatic_output" | while IFS= read -r line; do
        log_info "$line"
    done

    # Also append to log file
    echo "$collectstatic_output" >> "$LOG_FILE"

    if [[ $exit_code -eq 0 ]]; then
        log_info "Static files collected successfully"
        log_function_exit 0
        return 0
    else
        log_error "Failed to collect static files"
        log_error "Exit code: $exit_code"
        log_function_exit 1
        return 1
    fi
}

# Create NetBox superuser
create_netbox_superuser() {
    local install_path="$1"
    local username="$2"
    local email="$3"
    local password="$4"

    log_function_entry
    log_subsection "Creating NetBox Superuser"

    local manage_py="${install_path}/netbox/manage.py"
    local python_cmd="${install_path}/venv/bin/python"

    log_info "Creating superuser: $username"

    # Create superuser using Django management command
    # Pass password via environment variable for security
    local output
    local exit_code
    output=$(DJANGO_SUPERUSER_PASSWORD="$password" \
        $python_cmd "$manage_py" createsuperuser \
        --username "$username" \
        --email "$email" \
        --no-input 2>&1)
    exit_code=$?

    # Log output (to log file only, not console)
    echo "$output" >> "$LOG_FILE"

    # Check if superuser was created successfully
    if [[ $exit_code -eq 0 ]]; then
        log_info "Superuser created successfully: $username"
        log_security "NetBox superuser created: $username"
        log_info "You can now log in to NetBox with username '$username'"
        log_function_exit 0
        return 0
    elif echo "$output" | grep -q "already exists" || echo "$output" | grep -q "already taken"; then
        # Superuser already exists - this is not an error
        log_warn "Superuser '$username' already exists, skipping creation"
        log_function_exit 0
        return 0
    else
        # Actual error occurred
        log_error "Failed to create superuser"
        log_error "You may need to create the superuser manually using:"
        log_error "  cd $install_path/netbox"
        log_error "  source $install_path/venv/bin/activate"
        log_error "  python3 manage.py createsuperuser"
        log_function_exit 1
        return 1
    fi
}

# =============================================================================
# SYSTEMD SERVICES
# =============================================================================

# Install NetBox systemd services
install_netbox_services() {
    local install_path="$1"

    log_function_entry
    log_subsection "Installing Systemd Services"

    local contrib_dir="${install_path}/contrib"

    # Check for systemd service files in NetBox contrib
    if [[ ! -d "$contrib_dir" ]]; then
        log_error "NetBox contrib directory not found: $contrib_dir"
        log_function_exit 1
        return 1
    fi

    # Copy gunicorn configuration file
    log_info "Copying Gunicorn configuration..."
    local gunicorn_src="${contrib_dir}/gunicorn.py"
    local gunicorn_dst="${install_path}/gunicorn.py"

    if [[ -f "$gunicorn_src" ]]; then
        cp "$gunicorn_src" "$gunicorn_dst"
        chown netbox:netbox "$gunicorn_dst"
        chmod 644 "$gunicorn_dst"
        log_info "Gunicorn configuration copied to: $gunicorn_dst"
    else
        log_error "Gunicorn configuration not found: $gunicorn_src"
        log_function_exit 1
        return 1
    fi

    # Copy service files
    local services=("netbox.service" "netbox-rq.service")

    for service in "${services[@]}"; do
        local src="${contrib_dir}/${service}"
        local dst="/etc/systemd/system/${service}"

        if [[ -f "$src" ]]; then
            log_info "Installing service: $service"

            # Copy service file
            cp "$src" "$dst"

            # Replace installation path if needed (update ExecStart paths)
            if [[ "$install_path" != "/opt/netbox" ]]; then
                sed -i "s|/opt/netbox|${install_path}|g" "$dst"
                log_info "Updated service paths for custom installation directory"
            fi

            chmod 644 "$dst"
        else
            log_warn "Service file not found: $src"
        fi
    done

    # Reload systemd
    log_info "Reloading systemd daemon..."
    systemctl daemon-reload

    # Enable services
    for service in "${NETBOX_SERVICE}" "${NETBOX_RQ_SERVICE}"; do
        log_info "Enabling service: $service"
        systemctl enable "$service" >> "$LOG_FILE" 2>&1
    done

    log_function_exit 0
    return 0
}

# Start NetBox services
start_netbox_services() {
    log_function_entry
    log_subsection "Starting NetBox Services"

    local services=("$NETBOX_SERVICE" "$NETBOX_RQ_SERVICE")

    for service in "${services[@]}"; do
        log_info "Starting service: $service"

        if systemctl start "$service" 2>&1 | tee -a "$LOG_FILE"; then
            log_info "Service started: $service"
        else
            log_error "Failed to start service: $service"
            log_error "Check service status: systemctl status $service"
            log_function_exit 1
            return 1
        fi
    done

    # Wait for services to be active
    sleep 3

    # Verify services are running
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            log_info "Service is active: $service"
        else
            log_error "Service is not active: $service"
            systemctl status "$service" | tee -a "$LOG_FILE"
            log_function_exit 1
            return 1
        fi
    done

    log_function_exit 0
    return 0
}

# =============================================================================
# NGINX CONFIGURATION
# =============================================================================

# Generate self-signed SSL certificate
generate_self_signed_certificate() {
    local server_name="$1"
    local cert_path="$2"
    local key_path="$3"

    log_function_entry

    log_info "Generating self-signed SSL certificate..."
    log_info "Server name: $server_name"

    # Create certificate directory
    mkdir -p "$(dirname "$cert_path")"
    mkdir -p "$(dirname "$key_path")"

    # Generate self-signed certificate (valid for 365 days)
    if openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$key_path" \
        -out "$cert_path" \
        -subj "/CN=${server_name}" \
        2>&1 | tee -a "$LOG_FILE"; then

        # Set secure permissions
        chmod 644 "$cert_path"
        chmod 600 "$key_path"

        log_info "Self-signed certificate generated"
        log_warn "Self-signed certificates will trigger browser warnings"
        log_warn "For production use, replace with a valid certificate"

        log_function_exit 0
        return 0
    else
        log_error "Failed to generate self-signed certificate"
        log_function_exit 1
        return 1
    fi
}

# Configure Nginx for NetBox
configure_nginx() {
    local install_path="$1"
    local server_name="$2"
    local enable_ssl="$3"
    local ssl_mode="$4"
    local ssl_cert_path="$5"
    local ssl_key_path="$6"

    log_function_entry
    log_subsection "Configuring Nginx"

    local nginx_conf="/etc/nginx/conf.d/netbox.conf"

    log_info "Creating Nginx configuration: $nginx_conf"

    # Handle SSL configuration
    if [[ "$enable_ssl" == "yes" ]]; then
        log_info "SSL/TLS enabled"

        if [[ "$ssl_mode" == "self-signed" ]]; then
            # Generate self-signed certificate
            ssl_cert_path="/etc/pki/tls/certs/netbox-selfsigned.crt"
            ssl_key_path="/etc/pki/tls/private/netbox-selfsigned.key"

            generate_self_signed_certificate "$server_name" "$ssl_cert_path" "$ssl_key_path" || {
                log_error "Failed to generate SSL certificate"
                log_function_exit 1
                return 1
            }
        else
            # Validate user-provided certificates
            if [[ ! -f "$ssl_cert_path" ]]; then
                log_error "SSL certificate not found: $ssl_cert_path"
                log_function_exit 1
                return 1
            fi

            if [[ ! -f "$ssl_key_path" ]]; then
                log_error "SSL key not found: $ssl_key_path"
                log_function_exit 1
                return 1
            fi

            log_info "Using provided SSL certificate: $ssl_cert_path"
        fi

        # Create Nginx configuration with SSL
        cat > "$nginx_conf" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${server_name};

    # Redirect HTTP to HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${server_name};

    ssl_certificate ${ssl_cert_path};
    ssl_certificate_key ${ssl_key_path};

    # SSL security settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    client_max_body_size 25m;

    location /static/ {
        alias ${install_path}/netbox/static/;
    }

    location / {
        proxy_pass http://127.0.0.1:8001;
        proxy_set_header X-Forwarded-Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    else
        # Create Nginx configuration without SSL
        cat > "$nginx_conf" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${server_name};

    client_max_body_size 25m;

    location /static/ {
        alias ${install_path}/netbox/static/;
    }

    location / {
        proxy_pass http://127.0.0.1:8001;
        proxy_set_header X-Forwarded-Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    fi

    # Set permissions
    chmod 644 "$nginx_conf"

    # Test Nginx configuration
    log_info "Testing Nginx configuration..."

    if nginx -t >> "$LOG_FILE" 2>&1; then
        log_info "Nginx configuration is valid"
    else
        log_error "Nginx configuration test failed"
        log_function_exit 1
        return 1
    fi

    # Fix RHEL 8 nginx default_server conflict
    # RHEL 8 ships with 'default_server' in /etc/nginx/nginx.conf which
    # intercepts all traffic before our NetBox config can match.
    # RHEL 9+ does not have this issue.
    if [[ "$RHEL_VERSION" == "8" ]]; then
        local main_nginx_conf="/etc/nginx/nginx.conf"
        if grep -q "listen.*80.*default_server" "$main_nginx_conf"; then
            log_info "Removing default_server directive from nginx.conf (RHEL 8 compatibility)..."
            sed -i 's/listen       80 default_server;/listen       80;/' "$main_nginx_conf"
            sed -i 's/listen       \[::\]:80 default_server;/listen       [::]:80;/' "$main_nginx_conf"
            log_info "RHEL 8 nginx configuration adjusted for NetBox"
        fi
    fi

    # Configure firewall if firewalld is active
    if systemctl is-active --quiet firewalld; then
        log_info "Configuring firewall for HTTP/HTTPS access..."

        # Open HTTP port
        if firewall-cmd --permanent --add-service=http >> "$LOG_FILE" 2>&1; then
            log_info "Opened HTTP port (80) in firewall"
        else
            log_warn "Failed to open HTTP port in firewall (may already be open)"
        fi

        # Open HTTPS port (for future SSL configuration)
        if firewall-cmd --permanent --add-service=https >> "$LOG_FILE" 2>&1; then
            log_info "Opened HTTPS port (443) in firewall"
        else
            log_warn "Failed to open HTTPS port in firewall (may already be open)"
        fi

        # Reload firewall to apply changes
        if firewall-cmd --reload >> "$LOG_FILE" 2>&1; then
            log_info "Firewall configuration reloaded"
        else
            log_warn "Failed to reload firewall configuration"
        fi
    else
        log_info "Firewalld not active, skipping firewall configuration"
    fi

    # Enable and start Nginx
    log_info "Enabling Nginx service..."
    systemctl enable nginx >> "$LOG_FILE" 2>&1

    log_info "Starting Nginx service..."
    if systemctl restart nginx 2>&1 | tee -a "$LOG_FILE"; then
        log_info "Nginx started successfully"
        log_function_exit 0
        return 0
    else
        log_error "Failed to start Nginx"
        log_function_exit 1
        return 1
    fi
}

# =============================================================================
# INSTALLATION VALIDATION
# =============================================================================

# Verify NetBox installation
verify_installation() {
    local install_path="$1"
    local server_name="$2"
    local enable_ssl="$3"

    log_function_entry
    log_section "Installation Verification"

    # Check services
    log_subsection "Service Status"

    local services=("$NETBOX_SERVICE" "$NETBOX_RQ_SERVICE" "nginx" "redis")

    local all_active=true
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            log_info "✓ $service is active"
        else
            log_error "✗ $service is not active"
            all_active=false
        fi
    done

    if [[ "$all_active" != "true" ]]; then
        log_error "Some services are not running"
        log_function_exit 1
        return 1
    fi

    # Test HTTP connectivity
    log_subsection "HTTP Connectivity Test"

    local test_url
    if [[ "$enable_ssl" == "yes" ]]; then
        test_url="https://localhost"
    else
        test_url="http://localhost"
    fi

    log_info "Testing: $test_url"

    if curl -k -s -o /dev/null -w "%{http_code}" "$test_url" | grep -q "200\|301\|302"; then
        log_info "✓ HTTP connectivity successful"
    else
        log_warn "HTTP connectivity test returned unexpected status"
        log_warn "This may be normal if NetBox is still initializing"
    fi

    log_info "Installation verification complete"
    log_function_exit 0
    return 0
}

# =============================================================================
# INITIAL BACKUP
# =============================================================================

# Create initial installation backup
create_initial_backup() {
    local install_path="$1"
    local netbox_version="$2"

    log_function_entry
    log_subsection "Creating Initial Backup"

    # This will be implemented using rollback.sh functions
    # For now, just create backup directory structure

    local backup_base_dir="${BACKUP_DIR:-/var/backup/netbox-offline-installer}"
    local timestamp
    timestamp=$(date '+%Y%m%d-%H%M%S')
    local backup_dir="${backup_base_dir}/backup-${timestamp}-initial"

    log_info "Creating initial backup: $backup_dir"

    # Create backup directory
    if ! create_directory "$backup_dir" "root" "root" "750"; then
        log_warn "Failed to create backup directory (non-critical)"
        log_function_exit 0
        return 0
    fi

    # Backup configuration
    if [[ -f "$install_path/netbox/netbox/configuration.py" ]]; then
        cp "$install_path/netbox/netbox/configuration.py" "$backup_dir/configuration.py"
        log_info "Configuration backed up"
    fi

    # Create metadata file
    cat > "$backup_dir/metadata.txt" <<EOF
Backup Type: Initial Installation
NetBox Version: ${netbox_version}
Install Path: ${install_path}
Timestamp: $(date '+%Y-%m-%d %H:%M:%S %Z')
Hostname: $(hostname)
EOF

    log_info "Initial backup created"
    log_security "Initial installation backup: $backup_dir"

    log_function_exit 0
    return 0
}

# =============================================================================
# MAIN INSTALLATION ORCHESTRATION
# =============================================================================

# Main installation function
install_netbox_offline() {
    local package_dir="$1"
    local config_file="${2:-}"

    log_function_entry
    log_section "NetBox Offline Installation"

    # Pre-flight checks
    log_subsection "Pre-flight Checks"

    check_root_user

    local rhel_version
    rhel_version=$(check_supported_os)

    check_disk_space "/" "$MIN_DISK_SPACE_GB"

    # Validate package
    validate_package_structure "$package_dir" || {
        log_error "Package validation failed"
        log_function_exit 1
        return 1
    }

    # Validate package OS version matches target system
    if ! validate_package_os_match "$package_dir" "$rhel_version"; then
        log_error "Package OS version mismatch"
        log_error "Cannot proceed with installation"
        log_function_exit 1
        return 1
    fi

    # Get NetBox version from package
    local netbox_version
    netbox_version=$(get_package_netbox_version "$package_dir") || {
        log_error "Failed to determine NetBox version"
        log_function_exit 1
        return 1
    }

    log_info "NetBox version: v${netbox_version}"

    # Extract Python and PostgreSQL versions from manifest
    local python_version postgresql_version
    python_version=$(grep -oP 'Python Version:\s+\K[0-9.]+' "$package_dir/manifest.txt" 2>/dev/null)
    postgresql_version=$(grep -oP 'PostgreSQL Version:\s+\K[0-9]+' "$package_dir/manifest.txt" 2>/dev/null)

    if [[ -n "$python_version" ]]; then
        log_info "Python version: ${python_version}"
    fi

    if [[ -n "$postgresql_version" ]]; then
        log_info "PostgreSQL version: ${postgresql_version}"
    fi

    # Load configuration (if provided) or prompt interactively
    # For now, use defaults - configuration loading will be enhanced later

    local install_path="${INSTALL_PATH:-$DEFAULT_INSTALL_PATH}"
    local db_mode="${DB_MODE:-local}"
    local db_host="${DB_HOST:-localhost}"
    local db_port="${DB_PORT:-5432}"
    local db_name="${DB_NAME:-netbox}"
    local db_user="${DB_USER:-netbox}"

    # Process credentials
    local db_password
    db_password=$(process_config_token "DB_PASSWORD" "${DB_PASSWORD:-<generate>}")
    store_credential "DB_PASSWORD" "$db_password"

    local secret_key
    secret_key=$(process_config_token "SECRET_KEY" "${SECRET_KEY:-<generate>}")
    store_credential "SECRET_KEY" "$secret_key"

    # Prompt for superuser password early (if superuser creation enabled)
    local superuser_password
    if [[ "${CREATE_SUPERUSER:-yes}" == "yes" ]]; then
        superuser_password=$(process_config_token "SUPERUSER_PASSWORD" "${SUPERUSER_PASSWORD:-<prompt>}")
        store_credential "SUPERUSER_PASSWORD" "$superuser_password"
    fi

    # VM Snapshot (optional)
    if [[ "${VM_SNAPSHOT_ENABLED:-yes}" == "yes" ]]; then
        create_vm_snapshot_safe "netbox-pre-install"
    fi

    # Install RPM packages
    install_rpm_packages "$package_dir" || {
        log_error "RPM installation failed"
        log_function_exit 1
        return 1
    }

    # Configure PostgreSQL
    if [[ "$db_mode" == "local" ]]; then
        log_section "PostgreSQL Setup (Local)"

        initialize_postgresql || exit 1
        configure_postgresql_local || exit 1
        start_postgresql_service || exit 1
        create_netbox_database_local "$db_name" "$db_user" "$db_password" || exit 1
    else
        log_section "PostgreSQL Setup (Remote)"
        log_warn "Remote PostgreSQL configuration not fully implemented yet"
        # Remote mode implementation will be added
    fi

    # Start Redis
    start_redis_service || exit 1

    # Create netbox system user
    log_section "System User Creation"
    create_netbox_user "netbox" "$install_path" || exit 1

    # Install NetBox
    log_section "NetBox Installation"

    extract_netbox_source "$package_dir" "$install_path" || exit 1
    create_python_venv "$install_path" "$python_version" || exit 1
    install_python_dependencies "$package_dir" "$install_path" || exit 1

    # Configure NetBox
    local redis_host="${REDIS_HOST:-localhost}"
    local redis_port="${REDIS_PORT:-6379}"
    local redis_db="${REDIS_DATABASE:-0}"
    local redis_cache_db="${REDIS_CACHE_DATABASE:-1}"

    # Auto-detect allowed hosts if not specified in config
    local allowed_hosts
    if [[ -n "${ALLOWED_HOSTS}" ]]; then
        allowed_hosts="${ALLOWED_HOSTS}"
        log_info "Using ALLOWED_HOSTS from configuration: $allowed_hosts"
    else
        allowed_hosts=$(auto_detect_allowed_hosts)
        log_info "Auto-detected ALLOWED_HOSTS: $allowed_hosts"
    fi

    generate_netbox_configuration \
        "$install_path" \
        "$db_host" "$db_port" "$db_name" "$db_user" "$db_password" \
        "$redis_host" "$redis_port" "$redis_db" "$redis_cache_db" \
        "$allowed_hosts" "$secret_key" || exit 1

    # Database migrations
    run_netbox_migrations "$install_path" || exit 1

    # Collect static files
    collect_static_files "$install_path" || exit 1

    # Create superuser (if configured)
    if [[ "${CREATE_SUPERUSER:-yes}" == "yes" ]]; then
        local superuser_name="${SUPERUSER_USERNAME:-admin}"
        local superuser_email="${SUPERUSER_EMAIL:-admin@example.com}"

        # Retrieve superuser password from stored credentials (prompted earlier)
        local superuser_password
        superuser_password=$(get_credential "SUPERUSER_PASSWORD")

        # Create superuser (non-fatal if it fails - user can create manually later)
        if ! create_netbox_superuser "$install_path" "$superuser_name" "$superuser_email" "$superuser_password"; then
            log_warn "Superuser creation failed, but installation will continue"
            log_warn "You can create a superuser manually after installation completes"
        fi
    fi

    # Set file permissions
    set_secure_permissions "$install_path" "netbox" "netbox" "NetBox Installation" || exit 1

    # Install and start services
    install_netbox_services "$install_path" || exit 1
    start_netbox_services || exit 1

    # Configure Nginx
    local nginx_server_name="${NGINX_SERVER_NAME:-netbox.example.com}"
    local nginx_enable_ssl="${NGINX_ENABLE_SSL:-no}"
    local nginx_ssl_mode="${NGINX_SSL_MODE:-self-signed}"
    local nginx_ssl_cert="${NGINX_SSL_CERT_PATH:-}"
    local nginx_ssl_key="${NGINX_SSL_KEY_PATH:-}"

    configure_nginx "$install_path" "$nginx_server_name" "$nginx_enable_ssl" \
        "$nginx_ssl_mode" "$nginx_ssl_cert" "$nginx_ssl_key" || exit 1

    # Apply security hardening
    log_section "Security Hardening"

    # SELinux
    apply_security_hardening "$install_path" || {
        log_warn "Security hardening had some issues (non-critical)"
    }

    # Verify installation
    verify_installation "$install_path" "$nginx_server_name" "$nginx_enable_ssl"

    # Create initial backup
    create_initial_backup "$install_path" "$netbox_version"

    # Post-install STIG assessment (optional)
    run_stig_assessment "compliance"

    # Installation complete
    log_success_summary "NetBox Installation"

    log_info "NetBox v${netbox_version} installed successfully!"
    log_info "Installation path: $install_path"

    echo
    echo "================================================================================"
    echo "NetBox Installation Complete"
    echo "================================================================================"
    echo "Version:       v${netbox_version}"
    echo "Install Path:  $install_path"
    echo
    echo "Access Information:"
    echo "  You can access NetBox using any of these URLs:"
    # Display URLs for each detected host
    local protocol="http"
    if [[ "$nginx_enable_ssl" == "yes" ]]; then
        protocol="https"
    fi
    # Convert allowed_hosts space-separated list to array (disable globbing)
    set -f  # Disable filename globbing temporarily
    local hosts_array=($allowed_hosts)
    set +f  # Re-enable filename globbing
    for host in "${hosts_array[@]}"; do
        # Skip localhost, 127.0.0.1, and wildcards
        if [[ "$host" == "localhost" ]] || [[ "$host" == "127.0.0.1" ]] || [[ "$host" == "*" ]]; then
            continue
        fi
        # Only display if it looks like a hostname/IP (contains a dot OR is a valid single-word hostname)
        # Valid hostnames contain dots (FQDN/IP) or are alphanumeric with hyphens and NO file extensions
        if [[ "$host" =~ \. ]] || [[ "$host" =~ ^[a-zA-Z][a-zA-Z0-9-]*$ ]]; then
            echo "    ${protocol}://${host}"
        fi
    done
    echo
    if [[ "${CREATE_SUPERUSER:-yes}" == "yes" ]]; then
        echo "  Username:    ${SUPERUSER_USERNAME:-admin}"
        echo "  Password:    <as configured>"
    fi
    echo
    echo "Services:"
    # Get actual service statuses
    local netbox_status=$(systemctl is-active ${NETBOX_SERVICE} 2>/dev/null || echo "inactive")
    local netbox_rq_status=$(systemctl is-active ${NETBOX_RQ_SERVICE} 2>/dev/null || echo "inactive")
    local nginx_status=$(systemctl is-active nginx 2>/dev/null || echo "inactive")
    local postgres_status=$(systemctl is-active ${POSTGRESQL_SERVICE} 2>/dev/null || echo "inactive")
    local redis_status=$(systemctl is-active redis 2>/dev/null || echo "inactive")

    echo "  NetBox:      $netbox_status"
    echo "  NetBox RQ:   $netbox_rq_status"
    echo "  Nginx:       $nginx_status"
    echo "  PostgreSQL:  $postgres_status"
    echo "  Redis:       $redis_status"
    echo
    echo "Log File:      $LOG_FILE"
    echo "================================================================================"
    echo

    log_function_exit 0
    return 0
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize install module
init_install() {
    log_debug "Install module initialized"
}

# Auto-initialize when sourced
init_install

# End of install.sh
