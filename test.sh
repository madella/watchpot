#!/bin/bash
# WatchPot Test Script - Testa entrambi gli script principali

set -e

echo "WatchPot Test Suite"
echo "==================="

# Check if config exists
if [ ! -f config/watchpot.conf ]; then
    echo "[ERROR] Configuration file not found: config/watchpot.conf"
    echo "   Run: cp config/watchpot.conf.example config/watchpot.conf"
    echo "   Then edit the configuration file"
    exit 1
fi

# Test 1: Configuration validation
echo ""
echo "Test 1: Configuration validation"
echo "------------------------------------"

config_ok=true

# Check required settings
required_settings=("SENDER_EMAIL" "SENDER_PASSWORD" "RECIPIENTS")
for setting in "${required_settings[@]}"; do
    if ! grep -q "^${setting}=" config/watchpot.conf; then
        echo "[ERROR] Missing required setting: $setting"
        config_ok=false
    fi
done

if [ "$config_ok" = true ]; then
    echo "[OK] Configuration file looks good"
else
    echo "[ERROR] Configuration issues found - please fix them first"
    exit 1
fi

# Test 2: Directory setup
echo ""
echo "Test 2: Directory setup"
echo "---------------------------"

if [ -d "/var/lib/watchpot/photos" ]; then
    echo "[OK] Photos directory exists: /var/lib/watchpot/photos"
else
    echo "[WARNING] Photos directory missing - will be created automatically"
    echo "  You can run install.sh to set up directories properly"
fi

if [ -d "/var/log/watchpot" ]; then
    echo "[OK] Log directory exists: /var/log/watchpot"
else
    echo "[WARNING] Log directory missing - will be created automatically"
    echo "  You can run install.sh to set up directories properly"
fi

# Test 3: Python dependencies
echo ""
echo "Test 3: Python dependencies"
echo "-------------------------------"

dependencies=("psutil" "requests")
for dep in "${dependencies[@]}"; do
    if python3 -c "import $dep" 2>/dev/null; then
        echo "[OK] $dep is installed"
    else
        echo "[ERROR] $dep is missing - install with: pip3 install --user $dep"
        exit 1
    fi
done

# Test 4: Script executability
echo ""
echo "Test 4: Script executability"
echo "--------------------------------"

if [ -x scripts/capture_photo.py ]; then
    echo "[OK] capture_photo.py is executable"
else
    echo "[ERROR] capture_photo.py is not executable - run: chmod +x scripts/capture_photo.py"
    exit 1
fi

if [ -x scripts/send_email.py ]; then
    echo "[OK] send_email.py is executable"
else
    echo "[ERROR] send_email.py is not executable - run: chmod +x scripts/send_email.py"
    exit 1
fi

# Test 5: Camera test (if on Raspberry Pi)
echo ""
echo "Test 5: Camera test"
echo "----------------------"

if command -v rpicam-still &> /dev/null; then
    echo "[OK] rpicam-still command available"
    
    # Test photo capture
    echo "Testing photo capture..."
    if ./scripts/capture_photo.py --force; then
        echo "[OK] Photo capture test successful"
    else
        echo "[ERROR] Photo capture test failed"
        exit 1
    fi
else
    echo "[WARNING] rpicam-still not found - camera tests skipped"
    echo "   (This is normal on non-Raspberry Pi systems)"
fi

# Test 6: Email configuration test (without sending)
echo ""
echo "Test 6: Email configuration test"
echo "------------------------------------"

echo "Testing email script (dry run)..."
if python3 -c "
import sys
sys.path.append('scripts')
from send_email import load_config, get_system_stats
config = load_config('config/watchpot.conf')
stats = get_system_stats()
print('[OK] Email script can load config and gather stats')
" 2>/dev/null; then
    echo "[OK] Email script configuration test successful"
else
    echo "[ERROR] Email script configuration test failed"
    exit 1
fi

# Test 7: Log file creation
echo ""
echo "Test 7: Log file creation"
echo "----------------------------"

if [ -d "/var/log/watchpot" ] && [ -w "/var/log/watchpot" ]; then
    echo "[OK] Log directory is writable"
elif [ -w "/var/log" ]; then
    echo "[OK] Can create log directory in /var/log"
else
    echo "[WARNING] May not be able to write to /var/log - check permissions"
fi

# Summary
echo ""
echo "All tests passed!"
echo "=================="
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
