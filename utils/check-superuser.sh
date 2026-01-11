#!/bin/bash
#
# NetBox Superuser Diagnostic and Reset Script
# Version: 0.0.1
# Description: Check if superuser exists and optionally reset password
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored message
print_info() {
    echo -e "${CYAN}[INFO]${NC} $*"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root"
    exit 1
fi

# Default installation path
INSTALL_PATH="/opt/netbox"

# Check if NetBox is installed
if [[ ! -d "$INSTALL_PATH" ]]; then
    print_error "NetBox not found at $INSTALL_PATH"
    exit 1
fi

# Python and manage.py paths
PYTHON_CMD="$INSTALL_PATH/venv/bin/python"
MANAGE_PY="$INSTALL_PATH/netbox/manage.py"

if [[ ! -f "$PYTHON_CMD" ]] || [[ ! -f "$MANAGE_PY" ]]; then
    print_error "NetBox installation incomplete"
    exit 1
fi

echo
echo "================================================================================"
echo "                NetBox Superuser Diagnostic Tool"
echo "================================================================================"
echo

# Check database connectivity
print_info "Testing database connectivity..."
if sudo -u netbox $PYTHON_CMD $MANAGE_PY showmigrations &>/dev/null; then
    print_success "Database connection successful"
else
    print_error "Cannot connect to database"
    exit 1
fi

# List all superusers
print_info "Checking for superuser accounts..."
echo

superusers=$(sudo -u netbox $PYTHON_CMD $MANAGE_PY shell -c "
from django.contrib.auth import get_user_model
User = get_user_model()
for user in User.objects.filter(is_superuser=True):
    print(f'USER:{user.username}|{user.email}|{user.is_active}|{user.last_login}')
" 2>/dev/null | grep '^USER:' | sed 's/^USER://')

if [[ -z "$superusers" ]]; then
    print_error "No superuser accounts found!"
    echo
    print_info "Would you like to create a superuser now? [y/N]"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        print_info "Creating superuser interactively..."
        sudo -u netbox $PYTHON_CMD $MANAGE_PY createsuperuser
        exit 0
    else
        print_info "You can create a superuser manually by running:"
        print_info "  cd $INSTALL_PATH/netbox"
        print_info "  sudo -u netbox ../venv/bin/python manage.py createsuperuser"
        exit 1
    fi
else
    print_success "Found superuser account(s):"
    echo
    echo "Username         | Email                    | Active | Last Login"
    echo "---------------- | ------------------------ | ------ | ----------"
    while IFS='|' read -r username email active last_login; do
        printf "%-16s | %-24s | %-6s | %s\n" "$username" "$email" "$active" "$last_login"
    done <<< "$superusers"
    echo
fi

# Offer to reset password
read -r -p "$(echo -e "${CYAN}[INFO]${NC} Would you like to reset a superuser password? [y/N]: ")" response
if [[ "$response" =~ ^[Yy]$ ]]; then
    echo
    read -r -p "$(echo -e "${CYAN}[INFO]${NC} Enter username to reset password for: ")" username

    # Check if user exists
    user_exists=$(sudo -u netbox $PYTHON_CMD $MANAGE_PY shell -c "
from django.contrib.auth import get_user_model
User = get_user_model()
print('EXISTS:' + str(User.objects.filter(username='$username').exists()))
" 2>/dev/null | grep '^EXISTS:' | sed 's/^EXISTS://')

    if [[ "$user_exists" == "True" ]]; then
        print_info "Resetting password for user: $username"
        echo

        # Custom password input with visual feedback
        while true; do
            # Read password with asterisks
            password=""
            password_confirm=""

            # First password entry
            echo -n "New password: "
            while IFS= read -r -s -n1 char; do
                if [[ $char == $'\0' ]]; then
                    break
                fi
                if [[ $char == $'\177' ]]; then
                    # Backspace
                    if [[ -n "$password" ]]; then
                        password="${password%?}"
                        echo -ne "\b \b"
                    fi
                else
                    password+="$char"
                    echo -n "*"
                fi
            done
            echo

            # Password confirmation
            echo -n "Confirm password: "
            while IFS= read -r -s -n1 char; do
                if [[ $char == $'\0' ]]; then
                    break
                fi
                if [[ $char == $'\177' ]]; then
                    # Backspace
                    if [[ -n "$password_confirm" ]]; then
                        password_confirm="${password_confirm%?}"
                        echo -ne "\b \b"
                    fi
                else
                    password_confirm+="$char"
                    echo -n "*"
                fi
            done
            echo

            # Check if passwords match
            if [[ "$password" == "$password_confirm" ]]; then
                # Check password length (Django minimum is usually 8)
                if [[ ${#password} -lt 8 ]]; then
                    echo
                    print_warn "Password too short (minimum 8 characters). Please try again."
                    echo
                    continue
                fi

                # Set the password using Django's shell
                if sudo -u netbox $PYTHON_CMD $MANAGE_PY shell -c "
from django.contrib.auth import get_user_model
User = get_user_model()
user = User.objects.get(username='$username')
user.set_password('$password')
user.save()
print('SUCCESS')
" 2>/dev/null | grep -q "SUCCESS"; then
                    echo
                    print_success "Password changed successfully for user '$username'"
                else
                    echo
                    print_error "Failed to change password"
                    exit 1
                fi
                break
            else
                echo
                print_warn "Passwords do not match. Please try again."
                echo
            fi
        done
    else
        print_error "User '$username' not found"
        exit 1
    fi
else
    print_info "No changes made"
fi

echo
print_info "Diagnostic complete"
echo

exit 0
