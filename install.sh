#!/bin/bash
"""
Installation script for WatchPot
Installs and configures the photographic monitoring system
"""

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Utility functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to load configuration
load_config() {
    local config_file="config/watchpot.conf"
    
    if [ ! -f "$config_file" ]; then
        log_error "Configuration file $config_file not found!"
        exit 1
    fi
    
    log_info "Loading configuration from $config_file..."
    
    # Source the configuration file
    source "$config_file"
    
    # Validate required email settings
    if [ "$SENDER_EMAIL" = "your-email@gmail.com" ] || [ -z "$SENDER_EMAIL" ]; then
        log_error "Please configure SENDER_EMAIL in $config_file"
        exit 1
    fi
    
    if [ "$SENDER_PASSWORD" = "your-app-password" ] || [ -z "$SENDER_PASSWORD" ]; then
        log_error "Please configure SENDER_PASSWORD in $config_file"
        exit 1
    fi
    
    if [ "$RECIPIENTS" = "recipient1@example.com,recipient2@example.com" ] || [ -z "$RECIPIENTS" ]; then
        log_error "Please configure RECIPIENTS in $config_file"
        exit 1
    fi
    
    log_info "Configuration validated successfully"
}

# Check that script is run as root
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

log_info "=== Installing WatchPot ==="

# Load and validate configuration
load_config

# 1. Determine user to use
if [ -z "$WATCHPOT_USER" ]; then
    WATCHPOT_USER="pi"
    if ! id "$WATCHPOT_USER" &>/dev/null; then
        # If 'pi' user doesn't exist, use the current user who invoked sudo
        WATCHPOT_USER=${SUDO_USER:-$(whoami)}
        log_warn "User 'pi' not found, using '$WATCHPOT_USER' instead"
    else
        log_info "Using existing user '$WATCHPOT_USER'"
    fi
else
    log_info "Using configured user '$WATCHPOT_USER'"
fi

# Add user to video group for camera access
log_info "Adding user '$WATCHPOT_USER' to video group for camera access..."
usermod -a -G video "$WATCHPOT_USER"

# 2. Create necessary directories
log_info "Creating directories..."
mkdir -p /opt/watchpot/scripts
mkdir -p /etc/watchpot
mkdir -p /var/log/watchpot
mkdir -p /var/lib/watchpot/photos

# 3. Copy scripts
log_info "Copying scripts..."
cp scripts/* /opt/watchpot/scripts/
chmod +x /opt/watchpot/scripts/*

# 4. Generate configuration files from global config
log_info "Generating configuration files..."

# Generate photo config
cat > /etc/watchpot/config.json << EOF
{
    "photo_width": $PHOTO_WIDTH,
    "photo_height": $PHOTO_HEIGHT,
    "photo_quality": $PHOTO_QUALITY,
    "photos_dir": "/var/lib/watchpot/photos",
    "max_photos_keep": $MAX_PHOTOS_KEEP,
    "log_level": "$LOG_LEVEL",
    "send_error_logs": $SEND_ERROR_LOGS
}
EOF

# Generate email config
cat > /etc/watchpot/email_config.json << EOF
{
    "smtp_server": "$SMTP_SERVER",
    "smtp_port": $SMTP_PORT,
    "use_tls": $USE_TLS,
    "sender_email": "$SENDER_EMAIL",
    "sender_password": "$SENDER_PASSWORD",
    "recipients": [$(echo "$RECIPIENTS" | sed 's/,/", "/g' | sed 's/^/"/' | sed 's/$/"/')],
    "subject_template": "$EMAIL_SUBJECT",
    "body_template": "$EMAIL_BODY"
}
EOF

# 5. Set permissions
log_info "Setting permissions..."
chown -R "$WATCHPOT_USER":"$WATCHPOT_USER" /var/lib/watchpot
chown -R "$WATCHPOT_USER":"$WATCHPOT_USER" /var/log/watchpot
chown -R root:"$WATCHPOT_USER" /etc/watchpot
chmod 640 /etc/watchpot/*

# 6. Generate systemd service with correct user
log_info "Generating systemd service for user '$WATCHPOT_USER'..."
cat > /etc/systemd/system/watchpot.service << EOF
[Unit]
Description=WatchPot Photo Capture and Email Service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=$WATCHPOT_USER
Group=$WATCHPOT_USER
ExecStart=/opt/watchpot/scripts/watchpot.sh
WorkingDirectory=/opt/watchpot
StandardOutput=journal
StandardError=journal

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/log/watchpot /var/lib/watchpot

# Restart policy
Restart=no
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# 7. Generate systemd timer with configured time
log_info "Generating systemd timer for daily execution at $DAILY_TIME..."
cat > /etc/systemd/system/watchpot.timer << EOF
[Unit]
Description=WatchPot Timer - Take photo daily at $DAILY_TIME
Requires=watchpot.service

[Timer]
# Run daily at configured time
OnCalendar=*-*-* $DAILY_TIME:00
# Also run 5 minutes after boot
OnBootSec=5min
# Randomize execution by ±2 minutes to avoid overloads
RandomizedDelaySec=120
# Don't accumulate missed executions
Persistent=false

[Install]
WantedBy=timers.target
EOF
# 8. Reload systemd
log_info "Reloading systemd..."
systemctl daemon-reload

# 9. Install Python dependencies
log_info "Installing Python dependencies..."
apt update
apt install -y python3 python3-pip python3-psutil python3-requests

# 10. Check prerequisites
log_info "Checking prerequisites..."

# Check rpicam-still
if ! command -v rpicam-still &> /dev/null; then
    log_warn "rpicam-still not found. Install with: sudo apt install camera-apps"
fi

# Check Python3
if ! command -v python3 &> /dev/null; then
    log_error "Python3 not found. Install with: sudo apt install python3"
    exit 1
fi

log_info "=== Installation completed ==="
echo
log_info "WatchPot configured:"
log_info "  - User: $WATCHPOT_USER"
log_info "  - Daily execution time: $DAILY_TIME"
log_info "  - Email: $SENDER_EMAIL -> $RECIPIENTS"
echo
log_info "To enable the service:"
echo "  sudo systemctl enable watchpot.timer"
echo "  sudo systemctl start watchpot.timer"
echo
log_info "To test manually:"
echo "  sudo systemctl start watchpot.service"
echo
log_info "To view logs:"
echo "  sudo journalctl -u watchpot.service -f"
echo "  sudo tail -f /var/log/watchpot/watchpot.log"
