#!/bin/bash
"""
Test script to validate WatchPot configuration
Run this before installation to check your settings
"""

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

# Check if config file exists
CONFIG_FILE="config/watchpot.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Configuration file $CONFIG_FILE not found!"
    echo "Create it from the example in the README"
    exit 1
fi

log_info "=== Testing WatchPot Configuration ==="

# Load configuration
source "$CONFIG_FILE"

# Test 1: Check required email settings
log_test "Checking email configuration..."

if [ "$SENDER_EMAIL" = "your-email@gmail.com" ] || [ -z "$SENDER_EMAIL" ]; then
    log_error "SENDER_EMAIL not configured"
    exit 1
else
    log_info "Sender email: $SENDER_EMAIL"
fi

if [ "$SENDER_PASSWORD" = "your-app-password" ] || [ -z "$SENDER_PASSWORD" ]; then
    log_error "SENDER_PASSWORD not configured"
    exit 1
else
    log_info "Sender password: [CONFIGURED]"
fi

if [ "$RECIPIENTS" = "recipient1@example.com,recipient2@example.com" ] || [ -z "$RECIPIENTS" ]; then
    log_error "RECIPIENTS not configured"
    exit 1
else
    log_info "Recipients: $RECIPIENTS"
fi

# Test 2: Check time format
log_test "Checking time format..."
if [[ $DAILY_TIME =~ ^[0-2][0-9]:[0-5][0-9]$ ]]; then
    log_info "Daily time: $DAILY_TIME ✓"
else
    log_error "Invalid time format: $DAILY_TIME (should be HH:MM)"
    exit 1
fi

# Test 3: Check numeric values
log_test "Checking photo settings..."
if [[ $PHOTO_WIDTH =~ ^[0-9]+$ ]] && [ $PHOTO_WIDTH -gt 0 ]; then
    log_info "Photo width: $PHOTO_WIDTH ✓"
else
    log_error "Invalid photo width: $PHOTO_WIDTH"
    exit 1
fi

if [[ $PHOTO_HEIGHT =~ ^[0-9]+$ ]] && [ $PHOTO_HEIGHT -gt 0 ]; then
    log_info "Photo height: $PHOTO_HEIGHT ✓"
else
    log_error "Invalid photo height: $PHOTO_HEIGHT"
    exit 1
fi

if [[ $PHOTO_QUALITY =~ ^[0-9]+$ ]] && [ $PHOTO_QUALITY -ge 1 ] && [ $PHOTO_QUALITY -le 100 ]; then
    log_info "Photo quality: $PHOTO_QUALITY ✓"
else
    log_error "Invalid photo quality: $PHOTO_QUALITY (should be 1-100)"
    exit 1
fi

# Test 4: Check SMTP settings
log_test "Checking SMTP settings..."
log_info "SMTP server: $SMTP_SERVER:$SMTP_PORT"

if command -v telnet >/dev/null 2>&1; then
    log_test "Testing SMTP connection..."
    timeout 5 telnet "$SMTP_SERVER" "$SMTP_PORT" </dev/null >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        log_info "SMTP connection test: ✓"
    else
        log_warn "SMTP connection test failed (but this might be normal)"
    fi
else
    log_warn "telnet not available, skipping SMTP connection test"
fi

# Test 5: Check user setting
log_test "Checking user configuration..."
if [ -z "$WATCHPOT_USER" ]; then
    if id "pi" &>/dev/null; then
        log_info "Will use user: pi (auto-detected)"
    else
        log_info "Will use user: ${SUDO_USER:-$(whoami)} (auto-detected)"
    fi
else
    if id "$WATCHPOT_USER" &>/dev/null; then
        log_info "Will use user: $WATCHPOT_USER ✓"
    else
        log_error "Configured user '$WATCHPOT_USER' does not exist"
        exit 1
    fi
fi

# Test 6: Check prerequisites
log_test "Checking system prerequisites..."

if command -v python3 >/dev/null 2>&1; then
    log_info "Python3: ✓"
else
    log_error "Python3 not found. Install with: sudo apt install python3"
    exit 1
fi

if command -v rpicam-still >/dev/null 2>&1; then
    log_info "rpicam-still: ✓"
else
    log_warn "rpicam-still not found. Install with: sudo apt install camera-apps"
fi

# Summary
echo
log_info "=== Configuration Test Summary ==="
log_info "✓ Email settings configured correctly"
log_info "✓ Schedule: Daily at $DAILY_TIME"
log_info "✓ Photo settings valid"
log_info "✓ System prerequisites checked"
echo
log_info "🎉 Configuration looks good! Ready to install."
echo
echo "Next steps:"
echo "  sudo ./install.sh"
echo "  sudo systemctl enable watchpot.timer"
echo "  sudo systemctl start watchpot.timer"
