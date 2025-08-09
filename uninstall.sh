#!/bin/bash
# WatchPot Uninstall Script

set -e

echo "Uninstalling WatchPot..."

# Remove cron jobs
echo "Removing cron jobs..."
crontab -l 2>/dev/null | grep -v -E "(WatchPot|capture_photo|send_email)" | crontab - || true

echo "Cron jobs removed"

# Ask if user wants to remove data
echo
read -p "Remove photos and logs? [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf photos
    rm -rf logs
    echo "Data removed"
else
    echo "Data preserved"
fi

# Ask if user wants to remove config
echo
read -p "Remove configuration? [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -f config/watchpot.conf
    echo "Configuration removed"
else
    echo "Configuration preserved"
fi

echo
echo "WatchPot uninstall complete!"
echo
echo "Note: Python packages (psutil, requests) were not removed"
echo "Note: System packages (ssmtp, cron, etc.) were not removed"
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
