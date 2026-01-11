#!/bin/bash
#
# NetBox Offline Installer - Main Orchestrator
# Version: 0.0.1
# Description: Main entry point for NetBox offline installation system
#
# Created by: Kismet Agbasi (KismetG17@gmail.com)
# AI Collaborator: Claude Code (integrated with VS Code)
# Date Created: 12/27/2025
# Last Updated: 01/11/2026
#
# This script provides a unified interface for all NetBox installation,
# update, backup, and management operations.
#

# =============================================================================
# SCRIPT INITIALIZATION
# =============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load defaults
if [[ -f "$SCRIPT_DIR/config/defaults.conf" ]]; then
    source "$SCRIPT_DIR/config/defaults.conf"
fi

# Load library modules in specific order (logging first)
# This ensures logging functions are available to all modules
if [[ -f "$SCRIPT_DIR/lib/logging.sh" ]]; then
    source "$SCRIPT_DIR/lib/logging.sh"
fi

# Load remaining library modules
for lib in "$SCRIPT_DIR/lib"/*.sh; do
    if [[ -f "$lib" ]] && [[ "$lib" != "$SCRIPT_DIR/lib/logging.sh" ]]; then
        source "$lib"
    fi
done

# =============================================================================
# USAGE AND HELP
# =============================================================================

# Display usage information
display_usage() {
    cat <<'EOF'
NetBox Offline Installer
Version: 0.0.1

USAGE:
  netbox-installer.sh [OPTIONS] [COMMAND]

COMMANDS:
  build                 Build offline installation package (online mode)
  install               Install NetBox from offline package
  update                Update NetBox to new version
  rollback              Restore from backup
  uninstall             Completely remove NetBox
  backup                Create backup of current installation
  list-backups          List available backups
  interactive           Show interactive menu (default if no command)

OPTIONS:
  -c, --config FILE     Use configuration file (silent mode)
  -p, --package DIR     Offline package directory
  -b, --backup NAME     Backup name for rollback
  -v, --version         Show version information
  -h, --help            Show this help message
  --debug               Enable debug logging

EXAMPLES:
  # Interactive mode (menu)
  ./netbox-installer.sh

  # Build offline package (run on online system)
  ./netbox-installer.sh build

  # Install from offline package
  ./netbox-installer.sh install -p /path/to/netbox-offline-package

  # Install with configuration file (silent mode)
  ./netbox-installer.sh install -c install.conf -p /path/to/package

  # Update NetBox
  ./netbox-installer.sh update -p /path/to/new-package

  # Create backup
  ./netbox-installer.sh backup

  # Restore from backup
  ./netbox-installer.sh rollback -b backup-20240115-120000

  # Uninstall NetBox
  ./netbox-installer.sh uninstall

ENVIRONMENT VARIABLES:
  INSTALL_PATH          Installation directory (default: /opt/netbox)
  LOG_LEVEL             Logging verbosity: DEBUG, INFO, WARN, ERROR
  LOG_FILE              Log file path

For more information, see README.md or visit:
  https://github.com/netbox-community/netbox

EOF
}

# Display version information
display_version() {
    cat <<EOF
NetBox Offline Installer
Version: ${INSTALLER_VERSION}

Components:
  - Build Module:     Offline package creation
  - Install Module:   Air-gapped installation
  - Update Module:    Version upgrades
  - Rollback Module:  Backup and restore
  - Uninstall Module: Complete removal

Security Features:
  - SELinux support
  - FAPolicyD integration
  - Credential management
  - Audit logging

Platform Support:
  - RHEL 9
  - RHEL 10
  - Rocky Linux 9/10
  - AlmaLinux 9/10

EOF
}

# =============================================================================
# INTERACTIVE MENU
# =============================================================================

# Display interactive menu
display_interactive_menu() {
    clear

    # Detect NetBox version from latest build or default
    local netbox_version="v4.4.9"
    if [[ -f "./dist/netbox-offline-rhel9-v${netbox_version#v}.tar.gz" ]] || [[ -f "./manifest.txt" ]]; then
        netbox_version=$(grep -oP 'NetBox Version:\s+\K\S+' manifest.txt 2>/dev/null || echo "v4.4.9")
    fi

    cat <<EOF
================================================================================
          NetBox Community Edition ($netbox_version) Offline Installer
================================================================================

Please select an operation:

  1) Build offline package        (Run on online system)
  2) Install NetBox               (Run on offline system)
  3) Update NetBox                (Upgrade to new version)
  4) Backup current installation
  5) List available backups
  6) Restore from backup
  7) Uninstall NetBox
  8) Show version information
  9) Exit

================================================================================
EOF
}

# Handle interactive menu selection
handle_menu_selection() {
    local selection

    while true; do
        display_interactive_menu

        read -r -p "Enter selection [1-9]: " selection

        case "$selection" in
            1)
                echo
                log_section "Build Mode"
                log_info "This will create an offline installation package"
                log_info "Requires: Internet connectivity, RHEL 9 or 10"
                echo

                if confirm_action "Continue with build?" "y"; then
                    build_offline_package
                fi

                read -r -p "Press Enter to continue..."
                ;;

            2)
                echo
                log_section "Install Mode"

                local package_dir
                read -r -p "Enter path to offline package directory: " package_dir

                if [[ -z "$package_dir" ]]; then
                    log_error "Package directory is required"
                    read -r -p "Press Enter to continue..."
                    continue
                fi

                if [[ ! -d "$package_dir" ]]; then
                    log_error "Package directory not found: $package_dir"
                    read -r -p "Press Enter to continue..."
                    continue
                fi

                echo
                install_netbox_offline "$package_dir"

                read -r -p "Press Enter to continue..."
                ;;

            3)
                echo
                log_section "Update Mode"

                local update_package
                read -r -p "Enter path to update package directory: " update_package

                if [[ -z "$update_package" ]]; then
                    log_error "Update package directory is required"
                    read -r -p "Press Enter to continue..."
                    continue
                fi

                echo
                update_netbox "$update_package"

                read -r -p "Press Enter to continue..."
                ;;

            4)
                echo
                log_section "Backup Creation"

                local install_path
                read -r -p "Enter NetBox installation path [/opt/netbox]: " install_path
                install_path="${install_path:-/opt/netbox}"

                echo
                create_netbox_backup "$install_path" "manual"

                read -r -p "Press Enter to continue..."
                ;;

            5)
                echo
                list_backups
                read -r -p "Press Enter to continue..."
                ;;

            6)
                echo
                log_section "Restore from Backup"

                list_backups
                echo

                local backup_name
                read -r -p "Enter backup name to restore: " backup_name

                if [[ -z "$backup_name" ]]; then
                    log_error "Backup name is required"
                    read -r -p "Press Enter to continue..."
                    continue
                fi

                echo
                restore_from_backup "$backup_name"

                read -r -p "Press Enter to continue..."
                ;;

            7)
                echo
                log_section "Uninstall NetBox"

                local uninstall_path
                read -r -p "Enter NetBox installation path [/opt/netbox]: " uninstall_path
                uninstall_path="${uninstall_path:-/opt/netbox}"

                echo
                uninstall_netbox "$uninstall_path"

                read -r -p "Press Enter to continue..."
                ;;

            8)
                echo
                display_version
                read -r -p "Press Enter to continue..."
                ;;

            9)
                echo
                log_info "Exiting NetBox Offline Installer"
                exit 0
                ;;

            *)
                echo
                log_error "Invalid selection: $selection"
                sleep 2
                ;;
        esac
    done
}

# =============================================================================
# COMMAND LINE ARGUMENT PARSING
# =============================================================================

# Parse command line arguments
parse_arguments() {
    local command=""
    local config_file=""
    local package_dir=""
    local backup_name=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            build|install|update|rollback|uninstall|backup|list-backups|interactive)
                command="$1"
                shift
                ;;

            -c|--config)
                config_file="$2"
                shift 2
                ;;

            -p|--package)
                package_dir="$2"
                shift 2
                ;;

            -b|--backup)
                backup_name="$2"
                shift 2
                ;;

            --debug)
                LOG_LEVEL="DEBUG"
                shift
                ;;

            -v|--version)
                display_version
                exit 0
                ;;

            -h|--help)
                display_usage
                exit 0
                ;;

            *)
                log_error "Unknown option: $1"
                display_usage
                exit 1
                ;;
        esac
    done

    # Load configuration file if provided
    if [[ -n "$config_file" ]]; then
        if [[ -f "$config_file" ]]; then
            log_info "Loading configuration: $config_file"
            source "$config_file"
        else
            log_error "Configuration file not found: $config_file"
            exit 1
        fi
    fi

    # Execute command
    case "$command" in
        build)
            build_offline_package
            ;;

        install)
            if [[ -z "$package_dir" ]]; then
                log_error "Package directory required for install mode"
                log_error "Use: netbox-installer.sh install -p /path/to/package"
                exit 1
            fi

            install_netbox_offline "$package_dir"
            ;;

        update)
            if [[ -z "$package_dir" ]]; then
                log_error "Package directory required for update mode"
                log_error "Use: netbox-installer.sh update -p /path/to/package"
                exit 1
            fi

            update_netbox "$package_dir"
            ;;

        rollback)
            if [[ -z "$backup_name" ]]; then
                log_error "Backup name required for rollback mode"
                log_error "Use: netbox-installer.sh rollback -b backup-name"
                exit 1
            fi

            restore_from_backup "$backup_name"
            ;;

        uninstall)
            local install_path="${INSTALL_PATH:-/opt/netbox}"
            uninstall_netbox "$install_path"
            ;;

        backup)
            local install_path="${INSTALL_PATH:-/opt/netbox}"
            create_netbox_backup "$install_path" "manual"
            ;;

        list-backups)
            list_backups
            ;;

        interactive|"")
            # Default to interactive mode if no command specified
            handle_menu_selection
            ;;

        *)
            log_error "Unknown command: $command"
            display_usage
            exit 1
            ;;
    esac
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    # Display header
    display_header

    # Parse and execute command
    if [[ $# -eq 0 ]]; then
        # No arguments - interactive mode
        handle_menu_selection
    else
        # Command line mode
        parse_arguments "$@"
    fi
}

# Execute main function
main "$@"

# End of netbox-installer.sh
