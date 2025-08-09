#!/bin/bash
"""
Script to uninstall WatchPot
"""

set -euo pipefail

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

# Check that script is run as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR]${NC} This script must be run as root (use sudo)"
    exit 1
fi

log_info "=== Uninstalling WatchPot ==="

# 1. Stop and disable services
log_info "Stopping services..."
systemctl stop watchpot.timer 2>/dev/null || true
systemctl stop watchpot.service 2>/dev/null || true
systemctl disable watchpot.timer 2>/dev/null || true

# 2. Remove systemd files
log_info "Removing systemd services..."
rm -f /etc/systemd/system/watchpot.service
rm -f /etc/systemd/system/watchpot.timer
systemctl daemon-reload

# 3. Remove scripts
log_info "Removing scripts..."
rm -rf /opt/watchpot

# 4. Ask to remove configurations and data
echo
read -p "Remove configurations and photos? [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Removing configurations and data..."
    rm -rf /etc/watchpot
    rm -rf photos
    rm -rf logs
else
    log_warn "Keeping configurations and data in:"
    echo "  /etc/watchpot/"
    echo "  photos/"
    echo "  logs/"
fi

log_info "=== Uninstallation completed ==="
log_info "Note: WatchPot used the existing 'pi' user, so no user removal is needed."
