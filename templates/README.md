# NetBox Configuration Templates

This directory contains templates for NetBox and related service configurations.

## Template Files

Templates use variable substitution for dynamic configuration:

- `{{VARIABLE_NAME}}` - Replaced with actual values during installation

## Planned Templates

- `netbox-configuration.py.tmpl` - NetBox Django configuration
- `gunicorn.py.tmpl` - Gunicorn WSGI server configuration
- `nginx-netbox.conf.tmpl` - Nginx reverse proxy configuration
- `fapolicyd-netbox.rules.tmpl` - FAPolicyD trust rules
- `selinux-netbox.te.tmpl` - SELinux policy module (if needed)
- `netbox.service.tmpl` - Systemd service file for NetBox
- `netbox-rq.service.tmpl` - Systemd service file for NetBox RQ workers

## Usage

Templates are processed during installation by the install module (`lib/install.sh`).
