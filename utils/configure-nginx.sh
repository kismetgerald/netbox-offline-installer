#!/bin/bash
#
# Quick script to configure Nginx for NetBox
# Run this after successful NetBox installation
#

set -e

echo "Configuring Nginx for NetBox..."

# Configuration parameters
INSTALL_PATH="/opt/netbox"
SERVER_NAME="netbox.example.com"
ENABLE_SSL="no"

# Create Nginx configuration
NGINX_CONF="/etc/nginx/conf.d/netbox.conf"

echo "Creating Nginx configuration: $NGINX_CONF"

# Create HTTP-only configuration
cat > "$NGINX_CONF" <<'EOF'
server {
    listen 80;
    listen [::]:80;

    server_name netbox.example.com;
    client_max_body_size 25m;

    location /static/ {
        alias /opt/netbox/netbox/static/;
    }

    location /media/ {
        alias /opt/netbox/netbox/media/;
    }

    location / {
        proxy_pass http://127.0.0.1:8001;
        proxy_set_header X-Forwarded-Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        add_header P3P 'CP="ALL DSP COR PSAa PSDa OUR NOR ONL UNI COM NAV"';
    }
}
EOF

chmod 644 "$NGINX_CONF"
echo "✓ Nginx configuration created"

# Test Nginx configuration
echo "Testing Nginx configuration..."
if nginx -t; then
    echo "✓ Nginx configuration is valid"
else
    echo "✗ Nginx configuration test failed"
    exit 1
fi

# Apply SELinux contexts for Nginx if SELinux is installed
if command -v semanage &>/dev/null; then
    echo "Configuring SELinux for Nginx..."

    # Allow Nginx to connect to network
    setsebool -P httpd_can_network_connect 1 2>/dev/null || true

    # Set contexts for static and media files
    semanage fcontext -a -t httpd_sys_content_t "/opt/netbox/netbox/static(/.*)?" 2>/dev/null || \
        semanage fcontext -m -t httpd_sys_content_t "/opt/netbox/netbox/static(/.*)?" 2>/dev/null || true

    semanage fcontext -a -t httpd_sys_rw_content_t "/opt/netbox/netbox/media(/.*)?" 2>/dev/null || \
        semanage fcontext -m -t httpd_sys_rw_content_t "/opt/netbox/netbox/media(/.*)?" 2>/dev/null || true

    restorecon -R /opt/netbox/netbox/static/ 2>/dev/null || true
    restorecon -R /opt/netbox/netbox/media/ 2>/dev/null || true

    echo "✓ SELinux configured for Nginx"
fi

# Enable and start Nginx
echo "Enabling Nginx service..."
systemctl enable nginx

echo "Starting Nginx service..."
if systemctl restart nginx; then
    echo "✓ Nginx started successfully"
else
    echo "✗ Failed to start Nginx"
    echo "Check logs: journalctl -xeu nginx"
    exit 1
fi

# Wait a moment for service to start
sleep 2

# Test connectivity
echo ""
echo "Testing NetBox web interface..."
echo ""

if curl -I http://localhost/ 2>/dev/null | head -1; then
    echo ""
    echo "================================================================================"
    echo "✓ NetBox is now accessible via Nginx!"
    echo "================================================================================"
    echo ""
    echo "Access NetBox at:"
    echo "  http://$(hostname -f)/"
    echo "  http://$(hostname -I | awk '{print $1}')/"
    echo ""
    echo "Default credentials:"
    echo "  Username: admin"
    echo "  Password: (the password you set during installation)"
    echo ""
else
    echo "✗ Failed to connect to NetBox via Nginx"
    echo "Check Nginx logs: journalctl -xeu nginx"
fi
