#!/bin/bash
# Quick test script for 2 photos in 20 minutes + email

echo "Starting WatchPot test: 2 photos in 20 minutes + email"
echo "Current time: $(date)"

# Clean any existing photos from today
rm -rf photos/daily_$(date +%Y%m%d)

# Take 2 photos with 20 minute intervals (simulated with shorter time for testing)
echo "Photo 1/2 at $(date +%H:%M:%S)"
python3 scripts/capture_photo.py --force --time $(date +%H%M)

echo "Waiting 20 seconds (simulating 20 minutes)..."
sleep 20

echo "Photo 2/2 at $(date +%H:%M:%S)"
# Add 20 to minutes for second photo filename
python3 scripts/capture_photo.py --force --time $(date -d '+20 minutes' +%H%M 2>/dev/null || date -v+20M +%H%M)

echo "All photos captured. Waiting 10 seconds before sending email..."
sleep 10

echo "Sending email at $(date +%H:%M:%S)"
python3 scripts/send_email.py --test

echo "Test completed!"
echo "Check photos in: photos/daily_$(date +%Y%m%d)/"
