#!/bin/bash
#
# NetBox Offline Package Builder - Convenience Wrapper
# Version: 0.0.1
# Description: Quick wrapper for building offline packages
#
# Created by: Kismet Agbasi (KismetG17@gmail.com)
# AI Collaborator: Claude Code (integrated with VS Code)
# Date Created: 12/27/2025
# Last Updated: 01/11/2026
#
# This is a convenience script that calls the main installer in build mode.
# It provides a simple interface for users who only need to build packages.
#

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Main installer script
INSTALLER="$SCRIPT_DIR/netbox-installer.sh"

# Check if installer exists
if [[ ! -f "$INSTALLER" ]]; then
    echo "ERROR: Installer not found: $INSTALLER" >&2
    exit 1
fi

# Display banner
cat <<'EOF'
================================================================================
                  NetBox Offline Package Builder
================================================================================

This script will build an offline installation package for NetBox.

Requirements:
  - Internet connectivity (to download NetBox and dependencies)
  - RHEL 9 or 10 (must match target system)
  - Root privileges
  - ~5GB free disk space

The build process will:
  1. Query GitHub for latest stable NetBox release
  2. Download NetBox source code
  3. Collect all Python dependencies (wheels)
  4. Collect all RPM dependencies
  5. Package everything into a portable tarball

Output:
  ./dist/netbox-offline-rhel<version>-v<netbox-version>.tar.gz

================================================================================

EOF

# Confirm
read -r -p "Continue with build? [y/N]: " response

if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo "Build cancelled."
    exit 0
fi

echo
echo "Starting build process..."
echo

# Execute build
exec "$INSTALLER" build

# End of build-netbox-offline-package.sh
