#!/usr/bin/env python3
"""
Email sending script with attachments and system information
Uses standard library smtplib and email modules
"""

import os
import smtplib
import json
import logging
import sys
import subprocess
import socket
import requests
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.image import MIMEImage
from pathlib import Path
import datetime
import platform
import psutil

# Logging configuration
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/watchpot/email.log'),
        logging.StreamHandler()
    ]
)

logger = logging.getLogger(__name__)

class SystemInfo:
    """Collect system information for email reports"""
    
    @staticmethod
    def get_public_ip():
        """Get public IP address"""
        try:
            response = requests.get('https://api.ipify.org', timeout=10)
            return response.text.strip()
        except Exception as e:
            logger.warning(f"Could not get public IP: {e}")
            return "Unknown"
    
    @staticmethod
    def get_private_ip():
        """Get private IP address"""
        try:
            # Connect to a remote address to determine local IP
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
            s.close()
            return ip
        except Exception as e:
            logger.warning(f"Could not get private IP: {e}")
            return "Unknown"
    
    @staticmethod
    def get_cpu_temperature():
        """Get CPU temperature for Raspberry Pi"""
        try:
            # Try Raspberry Pi specific method
            with open('/sys/class/thermal/thermal_zone0/temp', 'r') as f:
                temp = int(f.read()) / 1000.0
                return f"{temp:.1f}°C"
        except Exception:
            try:
                # Alternative method using vcgencmd
                result = subprocess.run(['vcgencmd', 'measure_temp'], 
                                      capture_output=True, text=True)
                if result.returncode == 0:
                    temp_str = result.stdout.strip()
                    return temp_str.replace('temp=', '')
            except Exception:
                pass
            
            # Fallback for other systems
            try:
                if hasattr(psutil, 'sensors_temperatures'):
                    temps = psutil.sensors_temperatures()
                    if temps:
                        for name, entries in temps.items():
                            if entries:
                                return f"{entries[0].current:.1f}°C"
            except Exception:
                pass
            
            return "Unknown"
    
    @staticmethod
    def get_system_stats():
        """Get comprehensive system statistics"""
        try:
            stats = {
                'hostname': socket.gethostname(),
                'platform': platform.platform(),
                'cpu_percent': psutil.cpu_percent(interval=1),
                'memory_percent': psutil.virtual_memory().percent,
                'disk_usage': psutil.disk_usage('/').percent,
                'boot_time': datetime.datetime.fromtimestamp(psutil.boot_time()).strftime('%Y-%m-%d %H:%M:%S'),
                'uptime': str(datetime.datetime.now() - datetime.datetime.fromtimestamp(psutil.boot_time())).split('.')[0]
            }
            return stats
        except Exception as e:
            logger.warning(f"Could not get system stats: {e}")
            return {}
    
    @staticmethod
    def get_network_info():
        """Get network interface information"""
        try:
            interfaces = []
            for interface, addrs in psutil.net_if_addrs().items():
                for addr in addrs:
                    if addr.family == socket.AF_INET:
                        interfaces.append(f"{interface}: {addr.address}")
            return interfaces
        except Exception as e:
            logger.warning(f"Could not get network info: {e}")
            return []

class EmailSender:
    def __init__(self, config_file='/etc/watchpot/email_config.json'):
        """Initialize email sender with configuration"""
        self.config = self.load_config(config_file)
        
    def load_config(self, config_file):
        """Load email configuration from JSON file"""
        try:
            with open(config_file, 'r') as f:
                config = json.load(f)
                
            # Verify required fields
            required_fields = ['smtp_server', 'smtp_port', 'sender_email', 'sender_password', 'recipients']
            missing_fields = [field for field in required_fields if field not in config]
            
            if missing_fields:
                raise ValueError(f"Missing configuration fields: {missing_fields}")
                
            return config
            
        except FileNotFoundError:
            logger.error(f"Email configuration file {config_file} not found")
            raise
        except json.JSONDecodeError as e:
            logger.error(f"Error parsing email configuration file: {e}")
            raise
    
    def format_system_info(self, system_info, network_interfaces):
        """Format system information for email body"""
        public_ip = SystemInfo.get_public_ip()
        private_ip = SystemInfo.get_private_ip()
        temperature = SystemInfo.get_cpu_temperature()
        
        info_text = f"""
═══════════════════════════════════════
           SYSTEM INFORMATION
═══════════════════════════════════════

🌐 Network Information:
   • Public IP:  {public_ip}
   • Private IP: {private_ip}

🌡️  System Health:
   • CPU Temperature: {temperature}
   • CPU Usage:       {system_info.get('cpu_percent', 'Unknown')}%
   • Memory Usage:    {system_info.get('memory_percent', 'Unknown')}%
   • Disk Usage:      {system_info.get('disk_usage', 'Unknown')}%

💻 System Details:
   • Hostname:   {system_info.get('hostname', 'Unknown')}
   • Platform:   {system_info.get('platform', 'Unknown')}
   • Boot Time:  {system_info.get('boot_time', 'Unknown')}
   • Uptime:     {system_info.get('uptime', 'Unknown')}

🔌 Network Interfaces:"""
        
        for interface in network_interfaces:
            info_text += f"\n   • {interface}"
        
        info_text += "\n\n═══════════════════════════════════════"
        
        return info_text
    
    def get_error_logs(self):
        """Get recent error logs for inclusion in email"""
        error_logs = []
        log_files = [
            '/var/log/watchpot/capture_errors.log',
            '/var/log/watchpot/email.log',
            '/var/log/watchpot/watchpot.log'
        ]
        
        for log_file in log_files:
            try:
                if os.path.exists(log_file):
                    # Get last 20 lines of each log file
                    with open(log_file, 'r') as f:
                        lines = f.readlines()
                        recent_lines = lines[-20:] if len(lines) > 20 else lines
                        if recent_lines:
                            error_logs.append(f"\n--- {os.path.basename(log_file)} (last {len(recent_lines)} lines) ---")
                            error_logs.extend([line.rstrip() for line in recent_lines])
            except Exception as e:
                error_logs.append(f"Could not read {log_file}: {e}")
        
        return '\n'.join(error_logs) if error_logs else "No recent error logs found."
    
    def send_error_email(self, error_message):
        """Send email with error information when photo capture fails"""
        try:
            # Collect system information
            logger.info("Collecting system information for error email...")
            system_info = SystemInfo.get_system_stats()
            network_interfaces = SystemInfo.get_network_info()
            
            # Create email message
            msg = MIMEMultipart()
            msg['From'] = self.config['sender_email']
            msg['To'] = ', '.join(self.config['recipients'])
            
            # Dynamic subject with timestamp and error indication
            timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            subject = f"❌ WatchPot ERROR - {timestamp}"
            msg['Subject'] = subject
            
            # Error message body
            error_body = f"""❌ WatchPot Error Report - {timestamp}

PHOTO CAPTURE FAILED!

Error Details:
{error_message}

System information and recent logs are included below for troubleshooting.
"""
            
            # Format system information
            system_info_text = self.format_system_info(system_info, network_interfaces)
            
            # Always include error logs for error emails
            error_logs = self.get_error_logs()
            error_logs_text = f"\n\n═══════════════════════════════════════\n           RECENT ERROR LOGS\n═══════════════════════════════════════\n{error_logs}\n═══════════════════════════════════════"
            
            # Combine all information
            body = error_body + "\n" + system_info_text + error_logs_text
            
            msg.attach(MIMEText(body, 'plain'))
            
            # Send email
            logger.info(f"Connecting to {self.config['smtp_server']}:{self.config['smtp_port']}")
            
            with smtplib.SMTP(self.config['smtp_server'], self.config['smtp_port']) as server:
                # Enable TLS if configured
                if self.config.get('use_tls', True):
                    server.starttls()
                
                # Login
                server.login(self.config['sender_email'], self.config['sender_password'])
                
                # Send to all recipients
                for recipient in self.config['recipients']:
                    server.send_message(msg, to_addrs=[recipient])
                    logger.info(f"Error email sent successfully to: {recipient}")
            
            logger.info(f"Error email sent to {len(self.config['recipients'])} recipients")
            
        except Exception as e:
            logger.error(f"Error sending error email: {e}")
            raise

    def send_photo_email(self, photo_path):
        """Send email with photo attachment and system information"""
        try:
            # Verify photo file exists
            if not os.path.exists(photo_path):
                raise FileNotFoundError(f"Photo file not found: {photo_path}")
            
            # Collect system information
            logger.info("Collecting system information...")
            system_info = SystemInfo.get_system_stats()
            network_interfaces = SystemInfo.get_network_info()
            
            # Create email message
            msg = MIMEMultipart()
            msg['From'] = self.config['sender_email']
            msg['To'] = ', '.join(self.config['recipients'])
            
            # Dynamic subject with timestamp
            timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            subject = self.config.get('subject_template', 'WatchPot Alert - {timestamp}')
            msg['Subject'] = subject.format(timestamp=timestamp)
            
            # Message body with system information
            body_template = self.config.get('body_template', 
                'New photo captured by WatchPot on {timestamp}.\n\nSee attachment for details.')
            
            # Format system information
            system_info_text = self.format_system_info(system_info, network_interfaces)
            
            # Check if we should include error logs
            error_logs_text = ""
            if self.config.get('send_error_logs', True):
                error_logs = self.get_error_logs()
                if error_logs and error_logs != "No recent error logs found.":
                    error_logs_text = f"\n\n═══════════════════════════════════════\n           RECENT ERROR LOGS\n═══════════════════════════════════════\n{error_logs}\n═══════════════════════════════════════"
            
            # Combine user template with system info and error logs
            body = body_template.format(timestamp=timestamp) + "\n" + system_info_text + error_logs_text
            
            msg.attach(MIMEText(body, 'plain'))
            
            # Attach photo
            with open(photo_path, 'rb') as f:
                img_data = f.read()
                
            image = MIMEImage(img_data)
            image.add_header('Content-Disposition', 
                           f'attachment; filename="{os.path.basename(photo_path)}"')
            msg.attach(image)
            
            # Send email
            logger.info(f"Connecting to {self.config['smtp_server']}:{self.config['smtp_port']}")
            
            with smtplib.SMTP(self.config['smtp_server'], self.config['smtp_port']) as server:
                # Enable TLS if configured
                if self.config.get('use_tls', True):
                    server.starttls()
                
                # Login
                server.login(self.config['sender_email'], self.config['sender_password'])
                
                # Send to all recipients
                for recipient in self.config['recipients']:
                    server.send_message(msg, to_addrs=[recipient])
                    logger.info(f"Email sent successfully to: {recipient}")
            
            logger.info(f"Email with photo {photo_path} sent to {len(self.config['recipients'])} recipients")
            
        except Exception as e:
            logger.error(f"Error sending email: {e}")
            raise

def main():
    """Main function"""
    # Check if this is an error email (no photo path provided)
    if len(sys.argv) == 1:
        logger.error("Usage: send_email.py <photo_path> OR send_email.py --error '<error_message>'")
        return 1
    
    # Handle error email
    if len(sys.argv) == 3 and sys.argv[1] == "--error":
        error_message = sys.argv[2]
        try:
            sender = EmailSender()
            sender.send_error_email(error_message)
            logger.info("Error email sending process completed successfully")
            return 0
        except Exception as e:
            logger.error(f"Fatal error sending error email: {e}")
            return 1
    
    # Handle normal photo email
    if len(sys.argv) != 2:
        logger.error("Usage: send_email.py <photo_path> OR send_email.py --error '<error_message>'")
        return 1
    
    photo_path = sys.argv[1]
    
    try:
        sender = EmailSender()
        sender.send_photo_email(photo_path)
        logger.info("Email sending process completed successfully")
        return 0
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        return 1

if __name__ == "__main__":
    exit(main())
