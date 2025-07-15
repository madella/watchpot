#!/bin/bash
"""
Main orchestration script for photo capture and email sending
"""

set -euo pipefail

# Configuration
SCRIPT_DIR="/opt/watchpot/scripts"
LOG_DIR="/var/log/watchpot"
PYTHON_EXEC="/usr/bin/python3"
ERROR_LOG="$LOG_DIR/capture_errors.log"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_DIR/watchpot.log"
}

# Error logging function
log_error() {
    local error_msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $error_msg" | tee -a "$LOG_DIR/watchpot.log"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - WATCHPOT ERROR: $error_msg" >> "$ERROR_LOG"
}

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

log "=== Starting WatchPot ==="

# Capture photo
log "Capturing photo..."
PHOTO_PATH=$("$PYTHON_EXEC" "$SCRIPT_DIR/capture_photo.py" 2>&1)
CAPTURE_EXIT_CODE=$?

if [ $CAPTURE_EXIT_CODE -eq 0 ] && [ -n "$PHOTO_PATH" ]; then
    log "Photo captured successfully: $PHOTO_PATH"
    
    # Send email with photo
    log "Sending email with photo..."
    if "$PYTHON_EXEC" "$SCRIPT_DIR/send_email.py" "$PHOTO_PATH"; then
        log "Email sent successfully"
    else
        log_error "Email sending failed, but photo was captured"
        # Try to send error email
        "$PYTHON_EXEC" "$SCRIPT_DIR/send_email.py" --error "Photo captured successfully but email sending failed. Photo saved to: $PHOTO_PATH" || true
        exit 1
    fi
else
    log_error "Photo capture failed with exit code: $CAPTURE_EXIT_CODE"
    log_error "Capture output: $PHOTO_PATH"
    
    # Send error email
    log "Sending error notification email..."
    ERROR_MSG="Photo capture failed with exit code: $CAPTURE_EXIT_CODE. Details: $PHOTO_PATH"
    if "$PYTHON_EXEC" "$SCRIPT_DIR/send_email.py" --error "$ERROR_MSG"; then
        log "Error notification email sent successfully"
    else
        log_error "Failed to send error notification email"
    fi
    exit 1
fi

log "=== WatchPot completed successfully ==="
