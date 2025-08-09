#!/usr/bin/env python3
"""
WatchPot Email Sender Script
Sends daily email with all photos and system stats
"""

import os
import sys
import smtplib
import logging
import mimetypes
import socket
import requests
import datetime
import platform
import psutil
import subprocess
import time
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.image import MIMEImage
from pathlib import Path

def setup_logging(log_level='INFO'):
    """Setup logging"""
    log_dir = Path('logs')
    log_dir.mkdir(parents=True, exist_ok=True)
    
    level = getattr(logging, log_level.upper(), logging.INFO)
    logging.basicConfig(
        level=level,
        format='%(asctime)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler(log_dir / 'email.log'),
            logging.StreamHandler()
        ]
    )
    return logging.getLogger(__name__)

def load_config(config_file):
    """Load configuration"""
    config = {}
    try:
        with open(config_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    key = key.strip().lower()
                    value = value.strip().strip('"\'')
                    config[key] = value
        return config
    except Exception as e:
        print(f"Error loading config: {e}")
        sys.exit(1)

def get_system_stats():
    """Get comprehensive system information with retry logic"""
    stats = {
        'hostname': socket.gethostname(),
        'platform': platform.platform(),
        'timestamp': datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    }
    
    # Network info with retry
    for attempt in range(3):
        try:
            response = requests.get('https://api.ipify.org', timeout=10)
            stats['public_ip'] = response.text.strip()
            break
        except:
            if attempt == 2:
                stats['public_ip'] = 'Unknown'
            time.sleep(5) 
    
    # System health
    try:
        stats['cpu_percent'] = f"{psutil.cpu_percent(interval=1):.1f}%"
        stats['memory_percent'] = f"{psutil.virtual_memory().percent:.1f}%"
        stats['disk_percent'] = f"{psutil.disk_usage('/').percent:.1f}%"
        
        boot_time = datetime.datetime.fromtimestamp(psutil.boot_time())
        uptime = datetime.datetime.now() - boot_time
        stats['boot_time'] = boot_time.strftime('%Y-%m-%d %H:%M:%S')
        stats['uptime'] = str(uptime).split('.')[0]
    except Exception as e:
        stats['cpu_percent'] = 'Unknown'
        stats['memory_percent'] = 'Unknown'
        stats['disk_percent'] = 'Unknown'
        stats['boot_time'] = 'Unknown'
        stats['uptime'] = 'Unknown'
    
    # CPU temperature (Raspberry Pi)
    try:
        with open('/sys/class/thermal/thermal_zone0/temp', 'r') as f:
            temp = int(f.read()) / 1000.0
            stats['cpu_temperature'] = f"{temp:.1f}°C"
    except:
        try:
            result = subprocess.run(['vcgencmd', 'measure_temp'], 
                                  capture_output=True, text=True, timeout=5)
            if result.returncode == 0:
                stats['cpu_temperature'] = result.stdout.strip().replace('temp=', '')
            else:
                stats['cpu_temperature'] = 'Unknown'
        except:
            stats['cpu_temperature'] = 'Unknown'
    
    # Network interfaces
    try:
        interfaces = []
        for interface, addrs in psutil.net_if_addrs().items():
            for addr in addrs:
                if addr.family == socket.AF_INET and addr.address != '127.0.0.1':
                    interfaces.append(f"{interface}: {addr.address}")
        stats['network_interfaces'] = interfaces
    except:
        stats['network_interfaces'] = []
    
    return stats

def get_today_photos(photos_dir):
    """Get all photos from today"""
    today = datetime.date.today()
    daily_dir = Path(photos_dir) / f"daily_{today.strftime('%Y%m%d')}"
    
    if not daily_dir.exists():
        return []
    
    photos = list(daily_dir.glob("*.jpg"))
    photos.sort()
    return [str(p) for p in photos]

def create_system_info_text(stats):
    """Create formatted system information"""
    info = "\n═══════════════════════════════════════\n"
    info += "           SYSTEM INFORMATION\n"
    info += "═══════════════════════════════════════\n\n"
    
    info += "Network Information:\n"
    info += f"   - Public IP:  {stats.get('public_ip', 'Unknown')}\n"
    
    info += "System Health:\n"
    info += f"   - CPU Temperature: {stats.get('cpu_temperature', 'Unknown')}\n"
    info += f"   - CPU Usage:       {stats.get('cpu_percent', 'Unknown')}\n"
    info += f"   - Memory Usage:    {stats.get('memory_percent', 'Unknown')}\n"
    info += f"   - Disk Usage:      {stats.get('disk_percent', 'Unknown')}\n\n"
    
    info += "System Details:\n"
    info += f"   - Hostname:   {stats.get('hostname', 'Unknown')}\n"
    info += f"   - Platform:   {stats.get('platform', 'Unknown')}\n"
    info += f"   - Boot Time:  {stats.get('boot_time', 'Unknown')}\n"
    info += f"   - Uptime:     {stats.get('uptime', 'Unknown')}\n\n"
    
    if stats.get('network_interfaces'):
        info += "Network Interfaces:\n"
        for interface in stats.get('network_interfaces', []):
            info += f"   - {interface}\n"
        info += "\n"
    
    info += "═══════════════════════════════════════\n"
    return info

def attach_photo(msg, photo_path, logger):
    """Attach a photo to email with error handling"""
    try:
        if not os.path.exists(photo_path):
            logger.warning(f"Photo not found: {photo_path}")
            return False
        
        file_size = os.path.getsize(photo_path)
        if file_size == 0:
            logger.warning(f"Photo is empty: {photo_path}")
            return False
        
        # Determine MIME type
        mime_type, _ = mimetypes.guess_type(photo_path)
        if mime_type is None or not mime_type.startswith('image/'):
            mime_type = 'image/jpeg'
        
        main_type, sub_type = mime_type.split('/', 1)
        
        # Read and attach
        with open(photo_path, 'rb') as f:
            img_data = f.read()
        
        image = MIMEImage(img_data, _subtype=sub_type)
        filename = os.path.basename(photo_path)
        image.add_header('Content-Disposition', f'attachment; filename="{filename}"')
        
        msg.attach(image)
        logger.info(f"Attached: {filename} ({file_size} bytes)")
        return True
        
    except Exception as e:
        logger.error(f"Error attaching {photo_path}: {e}")
        return False

def send_daily_email(config, logger):
    """Send email with retry logic"""
    max_retries = int(config.get('max_retries', '3'))
    retry_delay = int(config.get('retry_delay', '30'))
    
    for attempt in range(max_retries):
        try:
            logger.info(f"Email attempt {attempt + 1}/{max_retries}")
            
            # Get today's photos
            photos_dir = config.get('photos_dir', 'photos')
            photo_paths = get_today_photos(photos_dir)
            
            logger.info(f"Found {len(photo_paths)} photos to send")
            
            # Get system stats
            stats = get_system_stats()
            
            # Create email
            msg = MIMEMultipart('mixed')
            msg['From'] = config['sender_email']
            msg['To'] = config['recipients']
            
            # Subject
            timestamp = stats.get('timestamp', datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'))
            today_date = datetime.date.today().strftime('%Y-%m-%d')
            subject = config.get('email_subject', 'WatchPot Daily Report - {date}')
            try:
                subject = subject.format(date=today_date, timestamp=timestamp)
            except KeyError as e:
                logger.warning(f"Template formatting error in subject: {e}")
                subject = f"WatchPot Daily Report - {today_date}"
            msg['Subject'] = subject
            
            # Body
            if photo_paths:
                capture_times = []
                for photo_path in photo_paths:
                    filename = os.path.basename(photo_path)
                    try:
                        # Extract time from filename like watchpot_20250809_0800.jpg
                        parts = filename.replace('.jpg', '').split('_')
                        if len(parts) >= 3:
                            time_str = parts[2]
                            if len(time_str) == 4:  # HHMM
                                formatted_time = f"{time_str[:2]}:{time_str[2:]}"
                                capture_times.append(formatted_time)
                    except:
                        pass
                
                body_template = config.get('email_body', 
                    'Hello! WatchPot captured {count} photos today at {times}. System info below.')
                try:
                    body = body_template.format(
                        count=len(photo_paths),
                        times=', '.join(capture_times) if capture_times else 'various times',
                        timestamp=timestamp,
                        date=today_date
                    )
                except KeyError as e:
                    logger.warning(f"Template formatting error in body: {e}")
                    body = f"Hello! WatchPot captured {len(photo_paths)} photos today. System info below."
            else:
                body = "Hello!\n\nNo photos were captured today. Please check the system.\n\nSystem information below."
                logger.warning("No photos found for today")
            
            # Add system info
            body += create_system_info_text(stats)
            
            # Attach body
            text_part = MIMEText(body, 'plain', 'utf-8')
            msg.attach(text_part)
            
            # Attach photos
            attached_count = 0
            for photo_path in photo_paths:
                if attach_photo(msg, photo_path, logger):
                    attached_count += 1
            
            logger.info(f"Attached {attached_count} photos")
            
            # Send email
            smtp_server = config.get('smtp_server', 'smtp.gmail.com')
            smtp_port = int(config.get('smtp_port', '587'))
            use_tls = config.get('use_tls', 'true').lower() == 'true'
            
            with smtplib.SMTP(smtp_server, smtp_port) as server:
                if use_tls:
                    server.starttls()
                
                server.login(config['sender_email'], config['sender_password'])
                
                recipients = [r.strip() for r in config['recipients'].split(',')]
                server.send_message(msg, to_addrs=recipients)
                
                logger.info(f"Email sent successfully to {len(recipients)} recipients")
                return True
                
        except Exception as e:
            logger.warning(f"Email attempt {attempt + 1} failed: {e}")
            if attempt < max_retries - 1:
                logger.info(f"Retrying in {retry_delay} seconds...")
                time.sleep(retry_delay)
    
    logger.error(f"Failed to send email after {max_retries} attempts")
    return False

def should_send_now(config):
    """Check if we should send email now based on schedule"""
    email_times = config.get('email_time', '19:00').split(',')
    current_dt = datetime.datetime.now()
    
    # Allow 10 minutes window for each scheduled time
    for scheduled_time in email_times:
        scheduled_time = scheduled_time.strip()
        if not scheduled_time:
            continue
            
        try:
            hour, minute = map(int, scheduled_time.split(':'))
            scheduled_dt = current_dt.replace(hour=hour, minute=minute, second=0, microsecond=0)
            
            # Check if current time is within 10 minutes of scheduled time
            time_diff = abs((current_dt - scheduled_dt).total_seconds())
            if time_diff <= 600:  # 10 minutes window
                return True
                
        except ValueError:
            continue
    
    return False

def main():
    import argparse
    
    parser = argparse.ArgumentParser(description='WatchPot Email Sender')
    parser.add_argument('--config', default='config/watchpot.conf', help='Configuration file')
    parser.add_argument('--force', action='store_true', help='Force send regardless of schedule')
    parser.add_argument('--test', action='store_true', help='Test mode - send with current photos')
    
    args = parser.parse_args()
    
    # Load configuration
    config = load_config(args.config)
    logger = setup_logging(config.get('log_level', 'INFO'))
    
    # Check if we should send
    if not args.force and not args.test:
        if not should_send_now(config):
            logger.info("Not scheduled to send email now")
            return
    
    logger.info("Starting email sending process")
    
    # Send email
    success = send_daily_email(config, logger)
    
    if success:
        logger.info("Email sent successfully")
        print("SUCCESS: Daily email sent")
        sys.exit(0)
    else:
        logger.error("Email sending failed")
        print("ERROR: Email sending failed")
        sys.exit(1)

if __name__ == "__main__":
    main()
