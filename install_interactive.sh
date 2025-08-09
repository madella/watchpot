#!/bin/bash
# WatchPot Interactive Installation Script

set -e

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

log_header() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

echo "=================================================="
echo "        WatchPot Interactive Installation"
echo "=================================================="
echo ""

# Step 1: System Detection
log_header "Step 1: System Detection"
echo "----------------------------------------"

# Check if running on Raspberry Pi
if command -v vcgencmd &> /dev/null; then
    log_info "Raspberry Pi detected"
    IS_RPI=true
else
    log_warn "Not a Raspberry Pi - camera functionality may be limited"
    IS_RPI=false
fi

# Check OS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    log_info "Linux system detected"
    IS_LINUX=true
else
    log_warn "Non-Linux system detected"
    IS_LINUX=false
fi

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    log_error "Please do not run this script as root"
    exit 1
fi

# Step 2: Prerequisites Check
log_header "Step 2: Prerequisites Check"
echo "----------------------------------------"

PREREQ_OK=true

# Check Python 3
if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
    log_info "Python 3 found: $PYTHON_VERSION"
else
    log_error "Python 3 not found"
    PREREQ_OK=false
fi

# Check pip3
if command -v pip3 &> /dev/null; then
    log_info "pip3 found"
else
    log_error "pip3 not found"
    PREREQ_OK=false
fi

if [ "$PREREQ_OK" = false ]; then
    echo ""
    log_error "Missing prerequisites. Please install them first:"
    echo "  sudo apt update"
    echo "  sudo apt install python3 python3-pip"
    exit 1
fi

# Step 3: Package Installation
log_header "Step 3: Package Installation"
echo "----------------------------------------"

if [ "$IS_LINUX" = true ]; then
    read -p "Install required system packages? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Updating package list..."
        sudo apt-get update
        
        log_info "Installing system packages..."
        sudo apt-get install -y \
            python3 \
            python3-pip \
            ssmtp \
            cron \
            curl
            
        if [ "$IS_RPI" = true ]; then
            log_info "Installing Raspberry Pi camera packages..."
            sudo apt-get install -y camera-apps
        fi
        
        log_info "System packages installed successfully"
    else
        log_info "Skipping system package installation"
    fi
else
    log_warn "Please install manually on non-Linux systems:"
    echo "   - Python 3.7+"
    echo "   - pip3"
    echo "   - cron or equivalent scheduler"
    echo "   - ssmtp or similar mail transfer agent"
fi

# Step 4: Python Dependencies
log_header "Step 4: Python Dependencies"
echo "----------------------------------------"

log_info "Installing Python dependencies..."
pip3 install --user psutil requests

# Verify installation
if python3 -c "import psutil, requests" 2>/dev/null; then
    log_info "Python dependencies installed successfully"
else
    log_error "Failed to install Python dependencies"
    exit 1
fi

# Step 5: Directory Setup
log_header "Step 5: Directory Setup"
echo "----------------------------------------"

log_info "Creating directories..."
sudo mkdir -p /var/lib/watchpot/photos
sudo mkdir -p /var/log/watchpot
sudo chown -R $USER:$USER /var/lib/watchpot /var/log/watchpot

# Verify directory permissions
if [ -w "/var/lib/watchpot" ] && [ -w "/var/log/watchpot" ]; then
    log_info "Directory permissions set correctly"
else
    log_error "Directory permission setup failed"
    exit 1
fi

# Step 6: Script Setup
log_header "Step 6: Script Setup"
echo "----------------------------------------"

log_info "Making scripts executable..."
chmod +x scripts/capture_photo.py
chmod +x scripts/send_email.py
chmod +x test.sh
chmod +x test_advanced.sh

if [ -x scripts/capture_photo.py ] && [ -x scripts/send_email.py ]; then
    log_info "Scripts are now executable"
else
    log_error "Failed to make scripts executable"
    exit 1
fi

# Step 7: Configuration Setup
log_header "Step 7: Configuration Setup"
echo "----------------------------------------"

if [ ! -f config/watchpot.conf ]; then
    log_info "Creating configuration from example..."
    cp config/watchpot.conf.example config/watchpot.conf
    log_warn "Configuration file created: config/watchpot.conf"
else
    log_info "Configuration file already exists"
fi

# Interactive configuration
echo ""
read -p "Would you like to configure email settings now? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    log_info "Email Configuration"
    echo "-------------------"
    
    echo "For Gmail, you need:"
    echo "1. Enable 2-factor authentication"
    echo "2. Generate an App Password"
    echo "3. Use the App Password (not your regular password)"
    echo ""
    
    read -p "Enter your email address: " SENDER_EMAIL
    read -s -p "Enter your email password/app-password: " SENDER_PASSWORD
    echo
    read -p "Enter recipient email(s) (comma-separated): " RECIPIENTS
    
    # Update configuration file
    sed -i.bak "s/SENDER_EMAIL=.*/SENDER_EMAIL=$SENDER_EMAIL/" config/watchpot.conf
    sed -i.bak "s/SENDER_PASSWORD=.*/SENDER_PASSWORD=$SENDER_PASSWORD/" config/watchpot.conf
    sed -i.bak "s/RECIPIENTS=.*/RECIPIENTS=$RECIPIENTS/" config/watchpot.conf
    rm -f config/watchpot.conf.bak
    
    log_info "Email configuration updated"
else
    log_warn "Please edit config/watchpot.conf manually before using WatchPot"
fi

# Step 8: Camera Test (if Raspberry Pi)
if [ "$IS_RPI" = true ]; then
    log_header "Step 8: Camera Test"
    echo "----------------------------------------"
    
    read -p "Test camera capture? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Testing camera..."
        if ./scripts/capture_photo.py --config config/watchpot.conf --force; then
            log_info "Camera test successful!"
        else
            log_error "Camera test failed. Check camera connection and permissions."
        fi
    fi
fi

# Step 9: Cron Jobs Setup
log_header "Step 9: Automated Scheduling Setup"
echo "----------------------------------------"

read -p "Install cron jobs for automatic operation? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    SCRIPT_DIR="$(pwd)/scripts"
    CONFIG_PATH="$(pwd)/config/watchpot.conf"
    
    # Create temporary cron file
    cat > /tmp/watchpot_cron << EOF
# WatchPot - Capture photos every 2 hours
0 */2 * * * $SCRIPT_DIR/capture_photo.py --config $CONFIG_PATH

# WatchPot - Send daily email at 19:00
0 19 * * * $SCRIPT_DIR/send_email.py --config $CONFIG_PATH

# WatchPot - Auto-restart capture if needed (every 10 minutes)
*/10 * * * * pgrep -f capture_photo.py || $SCRIPT_DIR/capture_photo.py --config $CONFIG_PATH --force
EOF
    
    # Install cron jobs
    crontab -l 2>/dev/null | grep -v "WatchPot" > /tmp/current_cron || true
    cat /tmp/current_cron /tmp/watchpot_cron | crontab -
    
    log_info "Cron jobs installed successfully"
    echo "Schedule:"
    echo "  - Photos every 2 hours"
    echo "  - Daily email at 19:00"
    echo "  - Auto-restart every 10 minutes"
    echo ""
    echo "To manage cron jobs:"
    echo "  View: crontab -l"
    echo "  Remove: crontab -l | grep -v WatchPot | crontab -"
    
    rm -f /tmp/watchpot_cron /tmp/current_cron
else
    log_info "Skipping cron installation"
fi

# Step 10: Final Test
log_header "Step 10: Installation Verification"
echo "----------------------------------------"

read -p "Run basic system test? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Running basic tests..."
    if ./test.sh; then
        log_info "Basic tests passed!"
    else
        log_warn "Some tests failed - check configuration"
    fi
fi

# Installation Complete
echo ""
echo "=================================================="
log_info "Installation Complete!"
echo "=================================================="
echo ""
echo "WatchPot has been installed successfully!"
echo ""
echo "Next Steps:"
echo "1. Review configuration: config/watchpot.conf"
if [ "$IS_RPI" = false ]; then
    echo "2. [NON-PI SYSTEM] Camera functionality will be limited"
fi
echo "3. Test manually:"
echo "   - Photo: ./scripts/capture_photo.py --force"
echo "   - Email: ./scripts/send_email.py --test"
echo "4. Run advanced tests: ./test_advanced.sh"
echo ""
echo "File Locations:"
echo "- Photos: /var/lib/watchpot/photos/"
echo "- Logs: /var/log/watchpot/"
echo "- Config: config/watchpot.conf"
echo ""
echo "For support and documentation, check the README.md file."
