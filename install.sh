#!/bin/bash
# WatchPot Installation Script

set -e

echo "Installing WatchPot (Simple 2-Script System)..."

# Check if running on Raspberry Pi (optional)
if command -v vcgencmd &> /dev/null; then
    echo "[OK] Raspberry Pi detected"
else
    echo "[WARNING] Not a Raspberry Pi - some features may not work"
fi

# Install required system packages
echo "Installing system packages..."
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Update package list
    sudo apt-get update
    
    # Install required packages
    sudo apt-get install -y \
        python3 \
        python3-pip \
        ssmtp \
        cron \
        curl
        
    echo "[OK] System packages installed"
else
    echo "[WARNING] Non-Linux system detected. Please install manually:"
    echo "   - Python 3.7+"
    echo "   - pip3"
    echo "   - cron or equivalent scheduler"
fi

# Install Python dependencies
echo "Installing Python dependencies..."
pip3 install --user psutil requests

# Create directories
echo "Creating directories..."
mkdir -p photos
mkdir -p logs

# Make scripts executable
echo "Making scripts executable..."
chmod +x scripts/capture_photo.py
chmod +x scripts/send_email.py

# Copy config if needed
if [ ! -f config/watchpot.conf ]; then
    echo "Creating configuration from example..."
    cp config/watchpot.conf.example config/watchpot.conf
    echo "[WARNING] Please edit config/watchpot.conf with your settings!"
fi

# Install cron jobs (optional)
read -p "Install cron jobs for automatic operation? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    SCRIPT_DIR="$(pwd)/scripts"
    
    # Create temporary cron file
    cat > /tmp/watchpot_cron << EOF
# WatchPot - Check for scheduled photos every 10 minutes
*/10 * * * * $SCRIPT_DIR/capture_photo.py --config $(pwd)/config/watchpot.conf

# WatchPot - Check for scheduled email every 10 minutes  
*/10 * * * * $SCRIPT_DIR/send_email.py --config $(pwd)/config/watchpot.conf

# WatchPot - Auto-restart capture if needed (every 30 minutes)
*/30 * * * * pgrep -f capture_photo.py || $SCRIPT_DIR/capture_photo.py --config $(pwd)/config/watchpot.conf --force
EOF
    
    # Install cron jobs
    crontab -l 2>/dev/null | grep -v "WatchPot" > /tmp/current_cron || true
    cat /tmp/current_cron /tmp/watchpot_cron | crontab -
    
    echo "[OK] Cron jobs installed"
    echo "To view: crontab -l"
    echo "To remove: crontab -l | grep -v WatchPot | crontab -"
    
    rm -f /tmp/watchpot_cron /tmp/current_cron
else
    echo "Skipping cron installation"
fi

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo "1. Edit config/watchpot.conf with your email settings"
echo "2. Test photo capture: ./scripts/capture_photo.py --force"
echo "3. Test email sending: ./scripts/send_email.py --test"
echo ""
echo "Photos will be saved to: ./photos/"
echo "Logs will be saved to: ./logs/"
echo ""
echo "Manual commands:"
echo "   Photo: ./scripts/capture_photo.py [--force|--cleanup]"
echo "   Email: ./scripts/send_email.py [--force|--test]"
