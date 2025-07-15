# WatchPot 📸📧

Automated photographic monitoring system for Raspberry Pi that captures photos daily and sends them via email with comprehensive system information.

## Features

- ✅ **Daily photo capture** at configurable time (default: 17:00)
- ✅ **Automatic email sending** with photo attachments
- ✅ **Systemd services** for automatic management
- ✅ **Single configuration file** for easy setup
- ✅ **Error handling** with email notifications when capture fails
- ✅ **Complete logging** and photo rotation
- ✅ **Uses existing user** (pi or current user - no new user creation)
- ✅ **Rich system information in emails:**
  - 🌐 Public and private IP addresses
  - 🌡️ CPU temperature monitoring
  - 📊 System health metrics (CPU, memory, disk usage)
  - ⏱️ Uptime and boot time
  - 🔌 Network interface details
  - 💻 Platform and hostname information
  - 📋 Recent error logs (when enabled)

## Requirements

### Hardware
- Raspberry Pi with camera module enabled
- Internet connection for email sending

### Software
- Raspberry Pi OS (Bullseye or later)
- Python 3.7+
- `rpicam-still` (included in camera-apps)
- Python packages: `psutil`, `requests`

```bash
sudo apt update
sudo apt install camera-apps python3 python3-pip python3-psutil python3-requests
```

## Installation

### 1. Clone the repository
```bash
git clone <repository-url>
cd watchpot
```

### 2. Run installation
```bash
chmod +x install.sh
sudo ./install.sh
```

### 3. Configure email
```bash
# Copy configuration template
sudo cp /etc/watchpot/email_config.json.example /etc/watchpot/email_config.json

# Edit configuration
sudo nano /etc/watchpot/email_config.json
```

#### Gmail Configuration
To use Gmail, you must:
1. Enable 2-factor authentication
2. Generate a specific "App Password"
3. Use the App Password in the configuration file

Example Gmail configuration:
```json
{
    "smtp_server": "smtp.gmail.com",
    "smtp_port": 587,
    "use_tls": true,
    "sender_email": "your-email@gmail.com",
    "sender_password": "your-app-password",
    "recipients": [
        "recipient1@example.com",
        "recipient2@example.com"
    ],
    "subject_template": "🔍 WatchPot Alert - {timestamp}",
    "body_template": "Hello!\\n\\nWatchPot has captured a new image at {timestamp}.\\n\\nPlease see the attachment for details and system information below.\\n\\nBest regards,\\nYour WatchPot System"
}
```

### 4. Enable and start the service
```bash
# Enable timer for automatic startup
sudo systemctl enable watchpot.timer

# Start timer
sudo systemctl start watchpot.timer

# Check status
sudo systemctl status watchpot.timer
```

## Configuration

### Main configuration files

#### `/etc/watchpot/config.json`
Photo capture configuration:
```json
{
    "photo_width": 1920,
    "photo_height": 1080,
    "photo_quality": 95,
    "photos_dir": "/var/lib/watchpot/photos",
    "max_photos_keep": 100
}
```

#### `/etc/watchpot/email_config.json`
Email sending configuration (see example above).

### Custom timer
Edit `/etc/systemd/system/watchpot.timer` to change frequency:

```ini
[Timer]
# Every hour
OnCalendar=hourly

# Every 15 minutes
OnCalendar=*:0/15

# Daily at 08:00
OnCalendar=*-*-* 08:00:00

# Weekdays only at 09:00
OnCalendar=Mon..Fri 09:00
```

After modifications:
```bash
sudo systemctl daemon-reload
sudo systemctl restart watchpot.timer
```

## Email Information

Each email includes comprehensive system information:

### 🌐 Network Information
- **Public IP**: Your external IP address (detected via api.ipify.org)
- **Private IP**: Local network IP address

### 🌡️ System Health
- **CPU Temperature**: Real-time Raspberry Pi temperature
- **CPU Usage**: Current CPU utilization percentage
- **Memory Usage**: RAM usage percentage  
- **Disk Usage**: Storage usage percentage

### 💻 System Details
- **Hostname**: System hostname
- **Platform**: Operating system details
- **Boot Time**: When the system was last started
- **Uptime**: How long the system has been running

### 🔌 Network Interfaces
- List of all network interfaces with their IP addresses

## Usage

### Main commands

```bash
# Timer status
sudo systemctl status watchpot.timer

# Manually trigger capture
sudo systemctl start watchpot.service

# Stop timer
sudo systemctl stop watchpot.timer

# Disable service
sudo systemctl disable watchpot.timer
```

### Monitoring

```bash
# Real-time logs
sudo journalctl -u watchpot.service -f

# Application logs
sudo tail -f /var/log/watchpot/watchpot.log
sudo tail -f /var/log/watchpot/capture.log
sudo tail -f /var/log/watchpot/email.log

# List captured photos
ls -la /var/lib/watchpot/photos/

# Next scheduled executions
sudo systemctl list-timers watchpot.timer
```

### Manual testing

```bash
# Test photo capture
sudo -u pi python3 /opt/watchpot/scripts/capture_photo.py

# Test email sending (replace with actual photo path)
sudo -u pi python3 /opt/watchpot/scripts/send_email.py /var/lib/watchpot/photos/watchpot_20250716_143022.jpg
```

## Project Structure

```
watchpot/
├── scripts/
│   ├── capture_photo.py    # Photo capture script
│   ├── send_email.py       # Email sending script
│   └── watchpot.sh         # Main orchestration script
├── systemd/
│   ├── watchpot.service    # Systemd service
│   └── watchpot.timer      # Systemd timer
├── config/
│   ├── config.json         # Photo configuration
│   └── email_config.json.example  # Email template
├── requirements.txt        # Python dependencies
├── install.sh              # Installation script
├── uninstall.sh           # Uninstallation script
└── README.md              # This documentation
```

### After installation

```
/opt/watchpot/scripts/      # Executable scripts
/etc/watchpot/              # Configuration files
/var/lib/watchpot/photos/   # Photo directory
/var/log/watchpot/          # Log files
```

## Security

- Service runs with the existing `pi` user (or current user if `pi` doesn't exist)
- Limited permissions with `ProtectSystem=strict`
- Isolated temporary directory with `PrivateTmp=true`
- No additional privileges with `NoNewPrivileges=true`
- User is automatically added to `video` group for camera access

## Troubleshooting

### Camera not working
```bash
# Check camera is enabled
sudo raspi-config
# Interface Options → Camera → Enable

# Test camera
rpicam-still -o test.jpg

# Check user in video group
groups pi
# or
groups $USER
```

### Emails not being sent
```bash
# Check configuration
sudo cat /etc/watchpot/email_config.json

# Test SMTP connection
telnet smtp.gmail.com 587

# Check email logs
sudo tail -f /var/log/watchpot/email.log
```

### Service won't start
```bash
# Check errors
sudo journalctl -u watchpot.service --no-pager

# Check permissions
ls -la /opt/watchpot/scripts/
ls -la /etc/watchpot/

# Test script manually
sudo -u pi /opt/watchpot/scripts/watchpot.sh
```

### Missing Python dependencies
```bash
# Install required packages
sudo apt install python3-psutil python3-requests

# Or use pip
sudo pip3 install psutil requests
```

## Supported Email Providers

### Gmail
- Server: `smtp.gmail.com`
- Port: `587` (TLS) or `465` (SSL)
- Requires App Password

### Outlook/Hotmail
- Server: `smtp-mail.outlook.com`
- Port: `587`

### Yahoo
- Server: `smtp.mail.yahoo.com`
- Port: `587` or `465`

### Custom providers
Simply modify `smtp_server` and `smtp_port` in the configuration.

## Sample Email Output

```
Hello!

WatchPot has captured a new image at 2025-07-16 14:30:22.

Please see the attachment for details and system information below.

Best regards,
Your WatchPot System

═══════════════════════════════════════
           SYSTEM INFORMATION
═══════════════════════════════════════

🌐 Network Information:
   • Public IP:  203.0.113.45
   • Private IP: 192.168.1.100

🌡️  System Health:
   • CPU Temperature: 42.3°C
   • CPU Usage:       15.2%
   • Memory Usage:    34.7%
   • Disk Usage:      28.9%

💻 System Details:
   • Hostname:   raspberrypi
   • Platform:   Linux-6.1.21-v8+-aarch64-with-glibc2.31
   • Boot Time:  2025-07-16 08:15:30
   • Uptime:     6:14:52

🔌 Network Interfaces:
   • eth0: 192.168.1.100
   • wlan0: 192.168.1.101
   • lo: 127.0.0.1

═══════════════════════════════════════
```

## License

MIT License - see LICENSE file for details.

## Contributing

Contributions are welcome! Open an issue or submit a pull request.

---

**Developed with ❤️ for Raspberry Pi**
