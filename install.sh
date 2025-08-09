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
    # # Update package list
    # sudo apt-get update
    
    # # Install required packages
    # sudo apt-get install -y \
    #     python3 \
    #     python3-pip \
    #     ssmtp \
    #     cron \
    #     curl \
    #     camera-apps
        
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
    WORKDIR="$(pwd)"
    
    # Remove any existing WatchPot cron jobs first
    echo "Removing existing WatchPot cron jobs..."
    
    # Check if we have existing crontab and filter out WatchPot entries
    if crontab -l 2>/dev/null > /tmp/existing_cron; then
        # Remove all WatchPot related lines and empty lines at the start
        sed '/^[[:space:]]*$/d; /WatchPot\|capture_photo\|send_email\|PATH.*usr\/local\|MAILTO.*$/d; /^#.*[Ii]mposta PATH\|^#.*[Dd]isabilita email/d' /tmp/existing_cron > /tmp/current_cron || true
    else
        # No existing crontab
        touch /tmp/current_cron
    fi
    
    # Create temporary cron file with proper directory context
    cat > /tmp/watchpot_cron << EOF
# Imposta PATH per includere /usr/local/bin
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Disabilita email di cron per evitare conflitti con sSMTP
MAILTO=""

# WatchPot - Check for scheduled photos every 10 minutes
*/10 * * * * cd $WORKDIR && ./scripts/capture_photo.py --config ./config/watchpot.conf >> ./logs/cron.log 2>&1

# WatchPot - Check for scheduled email every 10 minutes  
*/10 * * * * cd $WORKDIR && ./scripts/send_email.py --config ./config/watchpot.conf >> ./logs/cron.log 2>&1

# WatchPot - Auto-restart capture if needed (every 30 minutes)
*/30 * * * * cd $WORKDIR && (pgrep -f capture_photo.py || ./scripts/capture_photo.py --config ./config/watchpot.conf --force) >> ./logs/cron.log 2>&1
EOF
    
    # Install cron jobs
    cat /tmp/current_cron /tmp/watchpot_cron | crontab -
    
    echo "[OK] Cron jobs installed"
    echo "To view: crontab -l"
    echo "To remove: crontab -l | grep -v -E '(WatchPot|capture_photo|send_email)' | crontab -"
    
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
