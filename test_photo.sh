#!/bin/bash
"""
Test Photo Capture - WatchPot
Tests only the photo capture functionality
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

log_info "=== WatchPot Photo Capture Test ==="

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    log_warn "Running as root. On a real system, this would run as user 'pi' or current user."
fi

# Check prerequisites
log_test "Checking prerequisites..."

if ! command -v python3 >/dev/null 2>&1; then
    log_error "Python3 not found. Install with: sudo apt install python3"
    exit 1
fi

if ! command -v rpicam-still >/dev/null 2>&1; then
    log_error "rpicam-still not found. Install with: sudo apt install camera-apps"
    log_warn "On non-Pi systems, you can test with a mock capture"
    read -p "Continue with mock test? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
    MOCK_MODE=true
else
    log_info "rpicam-still found ✓"
    MOCK_MODE=false
fi

# Check Python dependencies
log_test "Checking Python dependencies..."
python3 -c "import json, datetime, logging, pathlib" 2>/dev/null
if [ $? -eq 0 ]; then
    log_info "Required Python modules available ✓"
else
    log_error "Missing Python modules"
    exit 1
fi

# Create test directories
TEST_DIR="/tmp/watchpot_test"
log_info "Creating test directory: $TEST_DIR"
mkdir -p "$TEST_DIR/photos"

# Load configuration if available
CONFIG_FILE="config/watchpot.conf"
if [ -f "$CONFIG_FILE" ]; then
    log_info "Loading configuration from $CONFIG_FILE"
    source "$CONFIG_FILE"
else
    log_warn "No configuration file found, using defaults"
    PHOTO_WIDTH=1920
    PHOTO_HEIGHT=1080
    PHOTO_QUALITY=95
fi

# Test photo capture
log_test "Testing photo capture..."
echo "Photo settings:"
echo "  - Size: ${PHOTO_WIDTH}x${PHOTO_HEIGHT}"
echo "  - Quality: ${PHOTO_QUALITY}"
echo "  - Output: $TEST_DIR/photos/"

if [ "$MOCK_MODE" = true ]; then
    # Mock photo capture for testing on non-Pi systems
    log_info "Creating mock photo (for testing purposes)..."
    TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
    PHOTO_PATH="$TEST_DIR/photos/watchpot_test_${TIMESTAMP}.jpg"
    
    # Create a simple test image using ImageMagick if available, or just a text file
    if command -v convert >/dev/null 2>&1; then
        convert -size ${PHOTO_WIDTH}x${PHOTO_HEIGHT} xc:lightblue \
                -pointsize 72 -fill black \
                -gravity center -annotate +0+0 "WatchPot\nTest Photo\n$TIMESTAMP" \
                "$PHOTO_PATH"
        log_info "Mock photo created with ImageMagick"
    else
        echo "WatchPot Test Photo - $TIMESTAMP" > "${PHOTO_PATH}.txt"
        PHOTO_PATH="${PHOTO_PATH}.txt"
        log_info "Mock text file created (ImageMagick not available)"
    fi
else
    # Real photo capture
    TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
    PHOTO_PATH="$TEST_DIR/photos/watchpot_test_${TIMESTAMP}.jpg"
    
    log_info "Capturing photo with rpicam-still..."
    
    # Run rpicam-still command
    CMD="rpicam-still -o $PHOTO_PATH --width $PHOTO_WIDTH --height $PHOTO_HEIGHT --quality $PHOTO_QUALITY --immediate --nopreview"
    echo "Command: $CMD"
    
    if $CMD; then
        log_info "Photo capture successful!"
    else
        log_error "Photo capture failed!"
        exit 1
    fi
fi

# Check if photo was created
if [ -f "$PHOTO_PATH" ]; then
    FILE_SIZE=$(stat -f%z "$PHOTO_PATH" 2>/dev/null || stat -c%s "$PHOTO_PATH" 2>/dev/null || echo "unknown")
    log_info "✓ Photo created successfully!"
    log_info "  File: $PHOTO_PATH"
    log_info "  Size: $FILE_SIZE bytes"
    
    # Try to get image info if available
    if command -v identify >/dev/null 2>&1 && [[ "$PHOTO_PATH" == *.jpg ]]; then
        IMAGE_INFO=$(identify "$PHOTO_PATH" 2>/dev/null || echo "Unable to read image info")
        log_info "  Info: $IMAGE_INFO"
    fi
else
    log_error "✗ Photo file was not created!"
    exit 1
fi

# Test the actual Python script if it exists
if [ -f "scripts/capture_photo.py" ]; then
    log_test "Testing Python capture script..."
    
    # Create a test config file
    mkdir -p "$TEST_DIR/config"
    cat > "$TEST_DIR/config/config.json" << EOF
{
    "photo_width": $PHOTO_WIDTH,
    "photo_height": $PHOTO_HEIGHT,
    "photo_quality": $PHOTO_QUALITY,
    "photos_dir": "$TEST_DIR/photos",
    "max_photos_keep": 10,
    "log_level": "INFO",
    "send_error_logs": true
}
EOF

    # Modify the script temporarily to use test config
    TEMP_SCRIPT="/tmp/test_capture.py"
    sed "s|/etc/watchpot/config.json|$TEST_DIR/config/config.json|g" scripts/capture_photo.py > "$TEMP_SCRIPT"
    sed -i.bak "s|/var/log/watchpot/|$TEST_DIR/|g" "$TEMP_SCRIPT"
    
    if python3 "$TEMP_SCRIPT"; then
        log_info "✓ Python capture script test successful!"
    else
        log_error "✗ Python capture script test failed!"
    fi
    
    rm -f "$TEMP_SCRIPT" "$TEMP_SCRIPT.bak"
fi

echo
log_info "=== Photo Capture Test Results ==="
log_info "✓ Test completed successfully!"
log_info "✓ Photo saved to: $PHOTO_PATH"
echo
log_info "You can now test email sending with:"
echo "  ./test_email.sh \"$PHOTO_PATH\""
echo
log_info "Or test the complete workflow with:"
echo "  ./test_full.sh"
echo
log_warn "Test files are in: $TEST_DIR"
log_warn "Remember to clean up test files when done: rm -rf $TEST_DIR"
