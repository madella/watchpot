#!/bin/bash
"""
Test Email Sending - WatchPot
Tests only the email functionality with or without photo attachment
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

show_usage() {
    echo "Usage: $0 [OPTIONS] [PHOTO_PATH]"
    echo
    echo "Options:"
    echo "  --error-test    Test error email (no photo)"
    echo "  --help         Show this help"
    echo
    echo "Examples:"
    echo "  $0                           # Test email without photo"
    echo "  $0 /path/to/photo.jpg       # Test email with photo"
    echo "  $0 --error-test             # Test error notification email"
}

# Parse arguments
ERROR_TEST=false
PHOTO_PATH=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --error-test)
            ERROR_TEST=true
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            PHOTO_PATH="$1"
            shift
            ;;
    esac
done

log_info "=== WatchPot Email Test ==="

# Check prerequisites
log_test "Checking prerequisites..."

if ! command -v python3 >/dev/null 2>&1; then
    log_error "Python3 not found. Install with: sudo apt install python3"
    exit 1
fi

# Check Python dependencies
log_test "Checking Python dependencies..."
MISSING_DEPS=()

python3 -c "import smtplib" 2>/dev/null || MISSING_DEPS+=("smtplib (standard library)")
python3 -c "import email" 2>/dev/null || MISSING_DEPS+=("email (standard library)")
python3 -c "import json" 2>/dev/null || MISSING_DEPS+=("json (standard library)")
python3 -c "import requests" 2>/dev/null || MISSING_DEPS+=("requests")
python3 -c "import psutil" 2>/dev/null || MISSING_DEPS+=("psutil")

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    log_error "Missing Python dependencies:"
    for dep in "${MISSING_DEPS[@]}"; do
        echo "  - $dep"
    done
    echo
    log_info "Install with: sudo apt install python3-requests python3-psutil"
    exit 1
else
    log_info "All Python dependencies available ✓"
fi

# Load and validate configuration
CONFIG_FILE="config/watchpot.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Configuration file not found: $CONFIG_FILE"
    log_info "Create and configure it first, then run this test"
    exit 1
fi

log_info "Loading configuration from $CONFIG_FILE"
source "$CONFIG_FILE"

# Validate email configuration
log_test "Validating email configuration..."

if [ "$SENDER_EMAIL" = "your-email@gmail.com" ] || [ -z "$SENDER_EMAIL" ]; then
    log_error "SENDER_EMAIL not configured in $CONFIG_FILE"
    exit 1
fi

if [ "$SENDER_PASSWORD" = "your-app-password" ] || [ -z "$SENDER_PASSWORD" ]; then
    log_error "SENDER_PASSWORD not configured in $CONFIG_FILE"
    exit 1
fi

if [ "$RECIPIENTS" = "recipient1@example.com,recipient2@example.com" ] || [ -z "$RECIPIENTS" ]; then
    log_error "RECIPIENTS not configured in $CONFIG_FILE"
    exit 1
fi

log_info "Email configuration:"
log_info "  SMTP: $SMTP_SERVER:$SMTP_PORT (TLS: $USE_TLS)"
log_info "  From: $SENDER_EMAIL"
log_info "  To: $RECIPIENTS"

# Test SMTP connection
log_test "Testing SMTP connection..."
if command -v telnet >/dev/null 2>&1; then
    if timeout 5 telnet "$SMTP_SERVER" "$SMTP_PORT" </dev/null >/dev/null 2>&1; then
        log_info "✓ SMTP server is reachable"
    else
        log_warn "⚠ SMTP server connection test failed (this might be normal)"
    fi
else
    log_warn "telnet not available, skipping connection test"
fi

# Create test directories
TEST_DIR="/tmp/watchpot_email_test"
mkdir -p "$TEST_DIR"

# Create test email configuration
cat > "$TEST_DIR/email_config.json" << EOF
{
    "smtp_server": "$SMTP_SERVER",
    "smtp_port": $SMTP_PORT,
    "use_tls": $USE_TLS,
    "sender_email": "$SENDER_EMAIL",
    "sender_password": "$SENDER_PASSWORD",
    "recipients": [$(echo "$RECIPIENTS" | sed 's/,/", "/g' | sed 's/^/"/' | sed 's/$/"/')],
    "subject_template": "$EMAIL_SUBJECT",
    "body_template": "$EMAIL_BODY",
    "send_error_logs": $SEND_ERROR_LOGS
}
EOF

# Handle photo path
if [ "$ERROR_TEST" = true ]; then
    log_test "Testing ERROR email (without photo)..."
    EMAIL_TYPE="error"
elif [ -n "$PHOTO_PATH" ]; then
    if [ ! -f "$PHOTO_PATH" ]; then
        log_error "Photo file not found: $PHOTO_PATH"
        log_info "Create a test photo first with: ./test_photo.sh"
        exit 1
    fi
    log_test "Testing email with photo attachment..."
    log_info "Photo: $PHOTO_PATH"
    EMAIL_TYPE="photo"
else
    log_test "Testing email without photo (system info only)..."
    EMAIL_TYPE="no-photo"
fi

# Create a temporary test photo if none provided and not error test
if [ "$EMAIL_TYPE" = "no-photo" ]; then
    TEST_PHOTO="$TEST_DIR/test_photo.txt"
    echo "WatchPot Email Test - $(date)" > "$TEST_PHOTO"
    PHOTO_PATH="$TEST_PHOTO"
    log_info "Created test file: $TEST_PHOTO"
fi

# Test the email script
if [ -f "scripts/send_email.py" ]; then
    log_test "Testing Python email script..."
    
    # Create temporary script with test config
    TEMP_SCRIPT="/tmp/test_email.py"
    sed "s|/etc/watchpot/email_config.json|$TEST_DIR/email_config.json|g" scripts/send_email.py > "$TEMP_SCRIPT"
    sed -i.bak "s|/var/log/watchpot/|$TEST_DIR/|g" "$TEMP_SCRIPT"
    
    # Create some test log files
    mkdir -p "$TEST_DIR"
    echo "$(date) - TEST: This is a test log entry" > "$TEST_DIR/capture_errors.log"
    echo "$(date) - INFO: Email test started" > "$TEST_DIR/email.log"
    echo "$(date) - INFO: WatchPot test execution" > "$TEST_DIR/watchpot.log"
    
    echo
    log_info "🚀 Sending test email..."
    echo "This may take a few seconds..."
    
    if [ "$ERROR_TEST" = true ]; then
        # Test error email
        if python3 "$TEMP_SCRIPT" --error "This is a test error message from WatchPot email test"; then
            log_info "✅ ERROR email test successful!"
            log_info "📧 Check your inbox for the error notification email"
        else
            log_error "❌ ERROR email test failed!"
            echo "Check the error messages above for details"
        fi
    else
        # Test normal email with photo
        if python3 "$TEMP_SCRIPT" "$PHOTO_PATH"; then
            log_info "✅ Email test successful!"
            log_info "📧 Check your inbox for the test email"
            if [ -f "$PHOTO_PATH" ]; then
                log_info "📎 Email should include photo attachment"
            fi
        else
            log_error "❌ Email test failed!"
            echo "Check the error messages above for details"
        fi
    fi
    
    rm -f "$TEMP_SCRIPT" "$TEMP_SCRIPT.bak"
else
    log_error "Email script not found: scripts/send_email.py"
    exit 1
fi

echo
log_info "=== Email Test Results ==="

if [ "$ERROR_TEST" = true ]; then
    log_info "✓ Error email test completed!"
    log_info "📧 Check your email for error notification"
else
    log_info "✓ Email test completed!"
    log_info "📧 Check your email for test message"
    if [ -n "$PHOTO_PATH" ] && [ -f "$PHOTO_PATH" ]; then
        log_info "📎 Email should include attachment"
    fi
fi

echo
log_info "Email should contain:"
log_info "  - System information (IP, temperature, etc.)"
log_info "  - Network interfaces"
log_info "  - Recent logs (if enabled)"
if [ "$ERROR_TEST" = false ] && [ -f "$PHOTO_PATH" ]; then
    log_info "  - Photo attachment"
fi

echo
log_warn "Test files created in: $TEST_DIR"
log_warn "Clean up with: rm -rf $TEST_DIR"

echo
log_info "Next steps:"
log_info "  1. Check your email inbox"
log_info "  2. Verify all information is correct"
log_info "  3. If successful, install WatchPot: sudo ./install.sh"
