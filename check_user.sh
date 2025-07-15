#!/bin/bash
"""
Helper script to check which user WatchPot will use
"""

# Determine user to use
WATCHPOT_USER="pi"
if ! id "$WATCHPOT_USER" &>/dev/null; then
    # If 'pi' user doesn't exist, use the current user who invoked sudo
    WATCHPOT_USER=${SUDO_USER:-$(whoami)}
    echo "User 'pi' not found, WatchPot will use: $WATCHPOT_USER"
else
    echo "WatchPot will use existing user: $WATCHPOT_USER"
fi

# Check if user is in video group
if groups "$WATCHPOT_USER" | grep -q '\bvideo\b'; then
    echo "✓ User $WATCHPOT_USER is in video group (camera access enabled)"
else
    echo "⚠ User $WATCHPOT_USER is NOT in video group (camera access may be limited)"
    echo "  Run: sudo usermod -a -G video $WATCHPOT_USER"
fi

# Check if user home directory exists
if [ -d "/home/$WATCHPOT_USER" ]; then
    echo "✓ User home directory exists: /home/$WATCHPOT_USER"
else
    echo "⚠ User home directory not found: /home/$WATCHPOT_USER"
fi
