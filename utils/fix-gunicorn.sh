#!/bin/bash
#
# Quick fix script for missing gunicorn.py
# This fixes the current installation without needing to reinstall
#

set -e

echo "Fixing NetBox installation..."

# Stop the failing service
echo "Stopping netbox service..."
systemctl stop netbox 2>/dev/null || true

# Copy gunicorn.py to expected location
echo "Copying gunicorn.py configuration..."
if [[ -f /opt/netbox/contrib/gunicorn.py ]]; then
    cp /opt/netbox/contrib/gunicorn.py /opt/netbox/gunicorn.py
    chown netbox:netbox /opt/netbox/gunicorn.py
    chmod 644 /opt/netbox/gunicorn.py
    echo "✓ Gunicorn configuration copied"
else
    echo "✗ Error: /opt/netbox/contrib/gunicorn.py not found"
    exit 1
fi

# Fix SELinux contexts for venv binaries
if command -v semanage &>/dev/null; then
    echo "Fixing SELinux contexts for Python virtual environment..."

    # Add context for venv binaries
    semanage fcontext -a -t bin_t "/opt/netbox/venv/bin(/.*)?" 2>/dev/null || \
        semanage fcontext -m -t bin_t "/opt/netbox/venv/bin(/.*)?" 2>/dev/null || true

    # Restore contexts
    restorecon -R /opt/netbox/venv/bin/
    echo "✓ SELinux contexts applied"
else
    echo "⚠ semanage not found, skipping SELinux context fix"
fi

# Start the service
echo "Starting netbox service..."
systemctl start netbox

# Wait a moment for service to start
sleep 2

# Check status
echo
echo "Service status:"
systemctl status netbox --no-pager -l

echo
echo "Done! Check the status above."
