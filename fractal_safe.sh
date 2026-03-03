#!/bin/bash
# Script: replace_fractal_with_safe.sh
# Description: Replace fractal service files with safe versions from GitHub

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Fractal Service Replacement Script ===${NC}"
echo "This script will replace fractal service files with safe versions"
echo ""

# GitHub repository details - YOUR CORRECT REPO
REPO_URL="https://raw.githubusercontent.com/School2281/purple_pickleberry/main"
BACKUP_DIR="/tmp/fractal_backup_$(date +%Y%m%d_%H%M%S)"

# Files to download (assuming these are the safe versions in your repo)
# If the files have different names, change these
SERVICE_FILE="fractal_safe.service"
CONFIG_FILE="fractal_server_safe.conf"

# Target locations
SERVICE_TARGET="/etc/systemd/system/fractal.service"
CONFIG_TARGET="/etc/nginx/sites-available/fractal_server.conf"
NGINX_ENABLED="/etc/nginx/sites-enabled/fractal_server.conf"

# Function to print colored messages
print_status() {
    echo -e "${YELLOW}[STATUS]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

# First, list what's available in the repo
print_status "Checking available files in GitHub repo..."
echo "Repo: https://github.com/School2281/purple_pickleberry"
echo ""

# Create backup directory
print_status "Creating backup directory: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

# Backup existing files
print_status "Backing up existing configuration files..."

if [[ -f "$SERVICE_TARGET" ]]; then
    cp "$SERVICE_TARGET" "$BACKUP_DIR/fractal.service.backup"
    print_success "Backed up $SERVICE_TARGET"
else
    print_status "No existing service file found"
fi

if [[ -f "$CONFIG_TARGET" ]]; then
    cp "$CONFIG_TARGET" "$BACKUP_DIR/fractal_server.conf.backup"
    print_success "Backed up $CONFIG_TARGET"
else
    print_status "No existing config file found"
fi

# Stop current fractal service
print_status "Stopping fractal service..."
systemctl stop fractal 2>/dev/null || true
systemctl disable fractal 2>/dev/null || true

# Try to download fractal_safe.service
print_status "Attempting to download $SERVICE_FILE from GitHub..."
if curl -s -f -o "/tmp/$SERVICE_FILE" "$REPO_URL/$SERVICE_FILE"; then
    print_success "Downloaded $SERVICE_FILE"
else
    print_error "Could not find $SERVICE_FILE in repo"
    echo "Checking if fractal_deploy.sh contains the service definition..."
    
    # Try to extract service from fractal_deploy.sh if it exists
    if curl -s -f -o "/tmp/fractal_deploy.sh" "$REPO_URL/fractal_deploy.sh"; then
        print_success "Downloaded fractal_deploy.sh"
        echo "Please check fractal_deploy.sh for service definitions"
        ls -la "/tmp/fractal_deploy.sh"
    else
        print_error "Could not download fractal_deploy.sh either"
        exit 1
    fi
fi

# Try to download fractal_server_safe.conf
print_status "Attempting to download $CONFIG_FILE from GitHub..."
if curl -s -f -o "/tmp/$CONFIG_FILE" "$REPO_URL/$CONFIG_FILE"; then
    print_success "Downloaded $CONFIG_FILE"
else
    print_error "Could not find $CONFIG_FILE in repo"
    echo "Available files in repo may be different"
fi

# If we have the service file, install it
if [[ -f "/tmp/$SERVICE_FILE" ]]; then
    print_status "Installing new service file..."
    cp "/tmp/$SERVICE_FILE" "$SERVICE_TARGET"
    chmod 644 "$SERVICE_TARGET"
    print_success "Installed $SERVICE_TARGET"
else
    print_error "No service file to install"
    echo "You may need to create the service file manually"
fi

# If we have the config file, install it
if [[ -f "/tmp/$CONFIG_FILE" ]]; then
    print_status "Installing new nginx configuration..."
    
    # Remove from sites-enabled if it exists (as symlink)
    if [[ -L "$NGINX_ENABLED" ]] || [[ -f "$NGINX_ENABLED" ]]; then
        rm -f "$NGINX_ENABLED"
    fi
    
    # Copy new config
    cp "/tmp/$CONFIG_FILE" "$CONFIG_TARGET"
    chmod 644 "$CONFIG_TARGET"
    
    # Create symlink in sites-enabled
    ln -s "$CONFIG_TARGET" "$NGINX_ENABLED"
    print_success "Installed $CONFIG_TARGET and enabled it"
else
    print_error "No config file to install"
fi

# Clean up temp files
rm -f "/tmp/$SERVICE_FILE" "/tmp/$CONFIG_FILE" "/tmp/fractal_deploy.sh" 2>/dev/null || true

# Reload systemd
print_status "Reloading systemd daemon..."
systemctl daemon-reload

# Test nginx configuration (only if config file exists)
if [[ -f "$CONFIG_TARGET" ]]; then
    print_status "Testing nginx configuration..."
    if nginx -t; then
        print_success "Nginx configuration is valid"
        print_status "Reloading nginx..."
        systemctl reload nginx || systemctl restart nginx
    else
        print_error "Nginx configuration test failed!"
        echo "Restoring from backup..."
        
        # Restore from backup if test fails
        if [[ -f "$BACKUP_DIR/fractal_server.conf.backup" ]]; then
            cp "$BACKUP_DIR/fractal_server.conf.backup" "$CONFIG_TARGET"
            ln -sf "$CONFIG_TARGET" "$NGINX_ENABLED"
            nginx -t
        fi
    fi
fi

# Enable and start new service (only if service file exists)
if [[ -f "$SERVICE_TARGET" ]]; then
    print_status "Enabling and starting new fractal service..."
    systemctl enable fractal
    systemctl start fractal
    
    # Check status
    print_status "Checking service status..."
    sleep 2
    if systemctl is-active --quiet fractal; then
        print_success "Fractal service is running!"
    else
        print_error "Fractal service failed to start"
        echo "Check status with: systemctl status fractal"
        systemctl status fractal --no-pager
    fi
fi

# Show what files are in the repo
echo ""
echo -e "${GREEN}=== Files in your GitHub repo ===${NC}"
echo "Repo: https://github.com/School2281/purple_pickleberry"
echo ""
echo "Main files:"
echo "  - fractal_deploy.sh (deployment script)"
echo ""
echo "If you need specific .service and .conf files, they should be added to the repo first"
echo ""

# Final summary
echo -e "${GREEN}=== Replacement Complete ===${NC}"
echo "Backup saved in: $BACKUP_DIR"
echo ""
echo "To check service status:"
echo "  sudo systemctl status fractal"
echo ""
echo "To check nginx:"
echo "  sudo nginx -t"
echo "  sudo systemctl status nginx"
echo ""
echo "To view logs:"
echo "  sudo journalctl -u fractal -f"
echo "  sudo tail -f /var/log/nginx/fractal_error.log"
echo "  sudo tail -f /var/log/nginx/fractal_access.log"
