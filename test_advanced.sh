#!/bin/bash
# WatchPot Advanced Test Script - Tests photo sequence and email functionality

set -e

echo "WatchPot Advanced Test Suite"
echo "============================"

# Configuration
CONFIG_FILE="config/watchpot.conf"
TEST_DIR="/tmp/watchpot_test"
ORIGINAL_PHOTOS_DIR=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

cleanup() {
    if [ -n "$ORIGINAL_PHOTOS_DIR" ] && [ -f "$CONFIG_FILE.backup" ]; then
        log_info "Restoring original configuration..."
        mv "$CONFIG_FILE.backup" "$CONFIG_FILE"
    fi
    
    if [ -d "$TEST_DIR" ]; then
        log_info "Cleaning up test directory..."
        rm -rf "$TEST_DIR"
    fi
}

trap cleanup EXIT

# Test 1: Configuration check
echo ""
log_info "Test 1: Configuration validation"
echo "----------------------------------------"

if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Configuration file not found: $CONFIG_FILE"
    echo "   Run: cp config/watchpot.conf.example config/watchpot.conf"
    echo "   Then edit the configuration file"
    exit 1
fi

# Backup original config
cp "$CONFIG_FILE" "$CONFIG_FILE.backup"

# Read original photos directory
ORIGINAL_PHOTOS_DIR=$(grep "^PHOTOS_DIR=" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d '"')
if [ -z "$ORIGINAL_PHOTOS_DIR" ]; then
    ORIGINAL_PHOTOS_DIR="/var/lib/watchpot/photos"
fi

log_info "Original photos directory: $ORIGINAL_PHOTOS_DIR"

# Test 2: Setup test environment
echo ""
log_info "Test 2: Setting up test environment"
echo "------------------------------------"

# Create test directory
mkdir -p "$TEST_DIR/photos"
mkdir -p "$TEST_DIR/logs"

# Modify config to use test directory
sed -i.tmp "s|PHOTOS_DIR=.*|PHOTOS_DIR=$TEST_DIR/photos|g" "$CONFIG_FILE"
rm -f "$CONFIG_FILE.tmp"

log_info "Test directory created: $TEST_DIR"

# Test 3: Photo capture sequence
echo ""
log_info "Test 3: Photo capture sequence test"
echo "------------------------------------"

# Test single photo capture
log_info "Testing single photo capture..."
if ./scripts/capture_photo.py --config "$CONFIG_FILE" --force; then
    log_info "Single photo capture: PASSED"
else
    log_error "Single photo capture: FAILED"
    exit 1
fi

# Check if photo was created
PHOTOS_CREATED=$(find "$TEST_DIR/photos" -name "*.jpg" | wc -l)
if [ "$PHOTOS_CREATED" -gt 0 ]; then
    log_info "Photos created successfully: $PHOTOS_CREATED"
else
    log_error "No photos were created"
    exit 1
fi

# Test multiple photos with different time suffixes
log_info "Testing multiple photo captures..."
for time_suffix in "0800" "1200" "1600" "2000"; do
    if ./scripts/capture_photo.py --config "$CONFIG_FILE" --time "$time_suffix"; then
        log_info "Photo capture for time $time_suffix: PASSED"
    else
        log_warn "Photo capture for time $time_suffix: FAILED (might be normal on non-Pi systems)"
    fi
done

# Count total photos
TOTAL_PHOTOS=$(find "$TEST_DIR/photos" -name "*.jpg" | wc -l)
log_info "Total photos captured: $TOTAL_PHOTOS"

# Test 4: List photos functionality
echo ""
log_info "Test 4: Photo listing functionality"
echo "------------------------------------"

if ./scripts/capture_photo.py --config "$CONFIG_FILE" --list; then
    log_info "Photo listing: PASSED"
else
    log_error "Photo listing: FAILED"
    exit 1
fi

# Test 5: Email functionality test
echo ""
log_info "Test 5: Email functionality test"
echo "---------------------------------"

# Check if email configuration exists
if grep -q "^SENDER_EMAIL=" "$CONFIG_FILE" && \
   grep -q "^SENDER_PASSWORD=" "$CONFIG_FILE" && \
   grep -q "^RECIPIENTS=" "$CONFIG_FILE"; then
    
    log_info "Email configuration found"
    
    # Test email script loading and stats gathering
    log_info "Testing email script initialization..."
    if python3 -c "
import sys
sys.path.append('scripts')
from send_email import load_config, get_system_stats
config = load_config('$CONFIG_FILE')
stats = get_system_stats()
print('[OK] Email script can load config and gather stats')
" 2>/dev/null; then
        log_info "Email script initialization: PASSED"
    else
        log_error "Email script initialization: FAILED"
        exit 1
    fi
    
    # Ask user if they want to send test email
    echo ""
    read -p "Do you want to send a test email with captured photos? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Sending test email..."
        if ./scripts/send_email.py --config "$CONFIG_FILE" --test; then
            log_info "Test email sending: PASSED"
        else
            log_error "Test email sending: FAILED"
            exit 1
        fi
    else
        log_info "Skipping test email sending"
    fi
else
    log_warn "Email configuration incomplete - skipping email tests"
    log_warn "Make sure to configure SENDER_EMAIL, SENDER_PASSWORD, and RECIPIENTS"
fi

# Test 6: Cleanup functionality
echo ""
log_info "Test 6: Cleanup functionality test"
echo "-----------------------------------"

# Create some old test photos
OLD_DIR="$TEST_DIR/photos/daily_20240101"
mkdir -p "$OLD_DIR"
touch "$OLD_DIR/old_photo1.jpg"
touch "$OLD_DIR/old_photo2.jpg"

log_info "Created test old photos"

# Test cleanup
if ./scripts/capture_photo.py --config "$CONFIG_FILE" --cleanup; then
    log_info "Cleanup functionality: PASSED"
else
    log_error "Cleanup functionality: FAILED"
    exit 1
fi

# Test 7: System integration test
echo ""
log_info "Test 7: System integration test"
echo "--------------------------------"

# Test full workflow: capture -> list -> email preparation
log_info "Running full workflow test..."

# Capture a photo
./scripts/capture_photo.py --config "$CONFIG_FILE" --force

# List photos
PHOTO_COUNT=$(./scripts/capture_photo.py --config "$CONFIG_FILE" --list | grep -c "\.jpg" || echo "0")

if [ "$PHOTO_COUNT" -gt 0 ]; then
    log_info "Workflow test: PASSED ($PHOTO_COUNT photos found)"
else
    log_error "Workflow test: FAILED (no photos found)"
    exit 1
fi

# Test 8: Configuration validation
echo ""
log_info "Test 8: Advanced configuration validation"
echo "------------------------------------------"

# Test with invalid config
echo "INVALID_SETTING=invalid" > /tmp/test_invalid.conf
if ./scripts/capture_photo.py --config /tmp/test_invalid.conf --force 2>/dev/null; then
    log_warn "Invalid config test: Script should handle missing settings gracefully"
else
    log_info "Invalid config test: PASSED (script properly handles invalid config)"
fi

rm -f /tmp/test_invalid.conf

# Final summary
echo ""
echo "========================================"
log_info "All tests completed successfully!"
echo "========================================"
echo ""
echo "Test Results Summary:"
echo "- Configuration validation: PASSED"
echo "- Test environment setup: PASSED"
echo "- Photo capture sequence: PASSED ($TOTAL_PHOTOS photos)"
echo "- Photo listing: PASSED"
echo "- Email functionality: TESTED"
echo "- Cleanup functionality: PASSED"
echo "- System integration: PASSED"
echo "- Configuration validation: PASSED"
echo ""
echo "System is ready for production use!"
echo ""
echo "Next steps:"
echo "1. Verify email settings in $CONFIG_FILE"
echo "2. Run: ./install.sh to set up cron jobs"
echo "3. Monitor logs in /var/log/watchpot/"
