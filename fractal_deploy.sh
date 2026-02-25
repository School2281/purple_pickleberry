#!/bin/bash

# Fractal Generator Deployment Script - Uses YOUR existing files
# Save as: deploy_fractal.sh
# Make executable: chmod +x deploy_fractal.sh
# Run: ./deploy_fractal.sh

# Self-heal permissions
[ -x "$0" ] || chmod +x "$0"

set -e  # Exit on error

# ============================================
# CONFIGURATION - CHANGE THESE TO MATCH YOUR SETUP
# ============================================

# Where your files are located (source)
SOURCE_DIR="/home/kali/purple_pickleberry"

# Where files will be deployed (destination)
APP_DIR="/var/www/html/fractal"
NGINX_CONF_DIR="/etc/nginx"
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
SYSTEMD_DIR="/etc/systemd/system"

# Log file
LOG_FILE="/tmp/fractal_deploy.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================
# HELPER FUNCTIONS
# ============================================

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "[WARNING] $(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# ============================================
# CHECK REQUIREMENTS
# ============================================

clear
echo "========================================="
echo "   Fractal Generator Deployment Script"
echo "   Using your existing files"
echo "========================================="
echo ""

# Check if source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    error "Source directory not found: $SOURCE_DIR"
fi

log "Found source directory: $SOURCE_DIR"
log "Log file: $LOG_FILE"

# Check for required files
log "Checking required files..."

REQUIRED_FILES=(
    "fractal_app.py"
    "fractal.service"
    "fractal_server.conf"
    "nginx.conf"
)

MISSING_FILES=0
for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$SOURCE_DIR/$file" ]; then
        log "  ✅ Found: $file"
    else
        warning "  ❌ Missing: $file"
        MISSING_FILES=1
    fi
done

if [ $MISSING_FILES -eq 1 ]; then
    echo ""
    echo -e "${YELLOW}Missing files detected. Do you want to:${NC}"
    echo "  1) Continue anyway (use what's there)"
    echo "  2) Exit and add missing files"
    read -p "Choose (1 or 2): " choice
    if [ "$choice" != "1" ]; then
        error "Please add missing files and run again"
    fi
fi

# ============================================
# BACKUP EXISTING CONFIGURATIONS
# ============================================

log "Backing up existing configurations..."

# Backup nginx.conf if it exists
if [ -f "$NGINX_CONF_DIR/nginx.conf" ]; then
    sudo cp "$NGINX_CONF_DIR/nginx.conf" "$NGINX_CONF_DIR/nginx.conf.backup.$(date +%Y%m%d_%H%M%S)"
    log "  ✅ Backed up existing nginx.conf"
fi

# Backup sites-enabled
if [ -d "$NGINX_CONF_DIR/sites-enabled" ]; then
    sudo cp -r "$NGINX_CONF_DIR/sites-enabled" "$NGINX_CONF_DIR/sites-enabled.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    log "  ✅ Backed up sites-enabled"
fi

# ============================================
# INSTALL DEPENDENCIES (if needed)
# ============================================

log "Checking system dependencies..."

# Check if nginx is installed
if ! command -v nginx &> /dev/null; then
    log "Installing nginx..."
    sudo apt update -qq
    sudo apt install -y -qq nginx
fi

# Check if pip3 is installed
if ! command -v pip3 &> /dev/null; then
    log "Installing pip3..."
    sudo apt update -qq
    sudo apt install -y -qq python3-pip
fi

# Install required Python packages
log "Installing Python packages..."
pip3 install flask numpy matplotlib pillow gunicorn >> "$LOG_FILE" 2>&1

# ============================================
# DEPLOY FILES
# ============================================

log "Deploying files..."

# Create destination directories
sudo mkdir -p "$APP_DIR"
sudo mkdir -p "$NGINX_SITES_AVAILABLE"

# Copy fractal_app.py
if [ -f "$SOURCE_DIR/fractal_app.py" ]; then
    log "Copying fractal_app.py to $APP_DIR/"
    sudo cp "$SOURCE_DIR/fractal_app.py" "$APP_DIR/"
    sudo chmod 755 "$APP_DIR/fractal_app.py"
fi

# Copy fractal.service
if [ -f "$SOURCE_DIR/fractal.service" ]; then
    log "Copying fractal.service to $SYSTEMD_DIR/"
    sudo cp "$SOURCE_DIR/fractal.service" "$SYSTEMD_DIR/"
    sudo chmod 644 "$SYSTEMD_DIR/fractal.service"
fi

# Copy fractal_server.conf
if [ -f "$SOURCE_DIR/fractal_server.conf" ]; then
    log "Copying fractal_server.conf to $NGINX_SITES_AVAILABLE/fractal"
    sudo cp "$SOURCE_DIR/fractal_server.conf" "$NGINX_SITES_AVAILABLE/fractal"
    sudo chmod 644 "$NGINX_SITES_AVAILABLE/fractal"
fi

# Copy nginx.conf (MAIN NGINX CONFIG)
if [ -f "$SOURCE_DIR/nginx.conf" ]; then
    log "Copying nginx.conf to $NGINX_CONF_DIR/"
    
    # Backup current nginx.conf
    if [ -f "$NGINX_CONF_DIR/nginx.conf" ]; then
        sudo mv "$NGINX_CONF_DIR/nginx.conf" "$NGINX_CONF_DIR/nginx.conf.backup"
    fi
    
    # Copy new config
    sudo cp "$SOURCE_DIR/nginx.conf" "$NGINX_CONF_DIR/"
    sudo chmod 644 "$NGINX_CONF_DIR/nginx.conf"
    log "  ✅ nginx.conf deployed"
fi

# Create symlink in sites-enabled
log "Enabling site in NGINX..."
sudo ln -sf "$NGINX_SITES_AVAILABLE/fractal" /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# Copy any additional static files (HTML, CSS, etc.)
log "Copying additional files..."
for file in "$SOURCE_DIR"/*; do
    if [ -f "$file" ] && [[ "$file" != *.py ]] && [[ "$file" != *.service ]] && [[ "$file" != *.conf ]]; then
        sudo cp "$file" "$APP_DIR/" 2>/dev/null || true
        log "  ✅ Copied $(basename "$file")"
    fi
done

# Set ownership
log "Setting permissions..."
sudo chown -R www-data:www-data "$APP_DIR"
sudo chmod -R 755 "$APP_DIR"

# ============================================
# START SERVICES
# ============================================

log "Starting services..."

# Reload systemd
sudo systemctl daemon-reload

# Enable and start fractal service
if [ -f "$SOURCE_DIR/fractal.service" ]; then
    log "Enabling fractal service..."
    sudo systemctl enable fractal.service >> "$LOG_FILE" 2>&1
    sudo systemctl start fractal.service >> "$LOG_FILE" 2>&1
fi

# Check if fractal service started
sleep 2
if sudo systemctl is-active --quiet fractal.service 2>/dev/null; then
    log "✅ Fractal service started successfully"
else
    warning "Fractal service may not have started. Check: sudo systemctl status fractal.service"
fi

# Test NGINX config
log "Testing NGINX configuration..."
if sudo nginx -t >> "$LOG_FILE" 2>&1; then
    sudo systemctl restart nginx
    log "✅ NGINX restarted successfully"
else
    error "NGINX configuration test failed. Check: sudo nginx -t"
fi

# ============================================
# TEST DEPLOYMENT
# ============================================

log "Testing deployment..."

# Wait for services to fully start
sleep 3

# Test Flask directly
if curl -s http://127.0.0.1:5000/status > /dev/null 2>&1; then
    log "✅ Flask app responding on port 5000"
else
    warning "Flask app not responding on port 5000"
fi

# Test through NGINX
if curl -s http://127.0.0.1/status > /dev/null 2>&1; then
    log "✅ NGINX proxy working"
else
    warning "NGINX proxy not working. Check: sudo nginx -t"
fi

# Test fractal generation (light test)
if curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1/light | grep -q "200"; then
    log "✅ Light endpoint working"
else
    warning "Light endpoint not working"
fi

# ============================================
# DEPLOYMENT SUMMARY
# ============================================

clear
echo "========================================="
echo "   Deployment Complete!"
echo "========================================="
echo ""

IP_ADDR=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")

echo -e "${GREEN}✅ Files deployed from:${NC} $SOURCE_DIR"
echo -e "${GREEN}✅ Application location:${NC} $APP_DIR"
echo -e "${GREEN}✅ Log file:${NC} $LOG_FILE"
echo ""
echo -e "${BLUE}Files deployed:${NC}"
ls -la "$SOURCE_DIR"/*.{py,service,conf} 2>/dev/null | while read line; do
    echo "  $line"
done
echo ""
echo -e "${BLUE}Access your fractal generator:${NC}"
echo "   Local:  http://127.0.0.1"
echo "   Network: http://$IP_ADDR"
echo ""
echo -e "${BLUE}Useful commands:${NC}"
echo "   View fractal logs:  sudo journalctl -u fractal.service -f"
echo "   View NGINX logs:    sudo tail -f /var/log/nginx/error.log"
echo "   View access logs:   sudo tail -f /var/log/nginx/access.log"
echo "   Restart fractal:    sudo systemctl restart fractal.service"
echo "   Restart NGINX:      sudo systemctl restart nginx"
echo "   Check status:       sudo systemctl status fractal.service"
echo "   Test NGINX config:  sudo nginx -t"
echo ""
echo -e "${YELLOW}Test endpoints:${NC}"
echo "   http://$IP_ADDR/status      - Status check"
echo "   http://$IP_ADDR/light       - Light test"
echo "   http://$IP_ADDR/viewer      - Interactive viewer"
echo "   http://$IP_ADDR/fractal?w=800&h=600  - Generate fractal"
echo ""
echo -e "${GREEN}Backups created:${NC}"
echo "   /etc/nginx/nginx.conf.backup.*"
echo "   /etc/nginx/sites-enabled.backup.*"
echo ""
echo "========================================="

# Save deployment info
cat > /tmp/fractal_deploy_info.txt << EOF
Deployment Date: $(date)
Source Directory: $SOURCE_DIR
Application Directory: $APP_DIR
Server IP: $IP_ADDR
Log File: $LOG_FILE

Files Deployed:
$(ls -la "$SOURCE_DIR"/*.{py,service,conf} 2>/dev/null)

Backups:
- /etc/nginx/nginx.conf.backup.$(date +%Y%m%d_%H%M%S)
- /etc/nginx/sites-enabled.backup.$(date +%Y%m%d_%H%M%S)
EOF

log "Deployment completed successfully!"
