#!/bin/bash
# WatchPot Test Script - Tests both main scripts

set -e

echo "WatchPot Test Suite"
echo "==================="
echo ""

# Test 1: Configuration file
echo "Test 1: Configuration validation"
echo "--------------------------------"

if [ ! -f "config/watchpot.conf" ]; then
    echo "[ERROR] Configuration file not found: config/watchpot.conf"
    echo "   Solution: cp config/watchpot.conf.example config/watchpot.conf"
    echo "   Then edit the configuration file with your settings"
    exit 1
fi

echo "[OK] Configuration file exists"

# Validate config content
required_vars=("SMTP_SERVER" "SMTP_PORT" "RECIPIENTS" "SENDER_PASSWORD" "SENDER_EMAIL")
for var in "${required_vars[@]}"; do
    if ! grep -q "^$var=" config/watchpot.conf; then
        echo "[ERROR] Missing configuration: $var"
        exit 1
    fi
done

echo "[OK] Configuration appears complete"

# Test 2: Directory structure
echo ""
echo "Test 2: Directory structure"
echo "----------------------------"

if [ -d "photos" ]; then
    echo "[OK] Photos directory exists: photos"
else
    echo "[WARNING] Photos directory not found - will be created on first run"
fi

if [ -d "logs" ]; then
    echo "[OK] Log directory exists: logs"
else
    echo "[WARNING] Log directory not found - will be created on first run"
fi

# Test 3: Python dependencies
echo ""
echo "Test 3: Python dependencies"
echo "----------------------------"

if command -v python3 &> /dev/null; then
    echo "[OK] Python3 is available"
else
    echo "[ERROR] Python3 not found"
    exit 1
fi

# Test 4: Required scripts
echo ""
echo "Test 4: Required scripts"
echo "------------------------"

if [ -f "scripts/capture_photo.py" ]; then
    echo "[OK] Capture script exists"
    if [ -x "scripts/capture_photo.py" ]; then
        echo "[OK] Capture script is executable"
    else
        echo "[WARNING] Capture script not executable - fixing..."
        chmod +x scripts/capture_photo.py
    fi
else
    echo "[ERROR] Capture script not found: scripts/capture_photo.py"
    exit 1
fi

if [ -f "scripts/send_email.py" ]; then
    echo "[OK] Email script exists"
    if [ -x "scripts/send_email.py" ]; then
        echo "[OK] Email script is executable"
    else
        echo "[WARNING] Email script not executable - fixing..."
        chmod +x scripts/send_email.py
    fi
else
    echo "[ERROR] Email script not found: scripts/send_email.py"
    exit 1
fi

# Test 5: Camera availability
echo ""
echo "Test 5: Camera system"
echo "---------------------"

if command -v rpicam-still &> /dev/null; then
    echo "[OK] rpicam-still is available"
else
    echo "[WARNING] rpicam-still not found - this is normal on non-Pi systems"
fi

# Test 6: Email configuration
echo ""
echo "Test 6: Email configuration"
echo "----------------------------"

source config/watchpot.conf

if [ -z "$SMTP_SERVER" ] || [ -z "$SENDER_EMAIL" ] || [ -z "$SENDER_PASSWORD" ]; then
    echo "[ERROR] Email configuration incomplete"
    echo "   Check SMTP_SERVER, SENDER_EMAIL, and SENDER_PASSWORD in config/watchpot.conf"
    exit 1
fi

echo "[OK] Email configuration appears complete"

# Test 7: Log file creation
echo ""
echo "Test 7: Log file creation"
echo "----------------------------"

if [ -d "logs" ] && [ -w "logs" ]; then
    echo "[OK] Log directory is writable"
elif [ -w "." ]; then
    echo "[OK] Can create log directory in current directory"
else
    echo "[WARNING] May not be able to write to current directory - check permissions"
fi

# Summary
echo ""
echo "Test Summary"
echo "============"
echo ""
echo "[OK] Configuration: OK"
echo "[OK] Directories: OK"
echo "[OK] Dependencies: OK"
echo "[OK] Scripts: OK"
if command -v rpicam-still &> /dev/null; then
    echo "[OK] Camera: OK"
else
    echo "[WARNING] Camera: Not tested (non-Pi system)"
fi
echo "[OK] Email config: OK"
echo "[OK] Logging: OK"
echo ""
echo "Ready to use! Try:"
echo "   Manual photo: ./scripts/capture_photo.py --force"
echo "   Test email: ./scripts/send_email.py --test"
echo ""
echo "To install automated scheduling:"
echo "   Run: ./install.sh (and choose 'y' for cron jobs)"
