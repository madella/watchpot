#!/usr/bin/env python3
"""
Photo capture script using rpicam-still on Raspberry Pi
"""

import os
import subprocess
import datetime
import logging
import json
from pathlib import Path

# Logging configuration
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/watchpot/capture.log'),
        logging.StreamHandler()
    ]
)

logger = logging.getLogger(__name__)

class PhotoCapture:
    def __init__(self, config_file='/etc/watchpot/config.json'):
        """Initialize photo capturer with configuration"""
        self.config = self.load_config(config_file)
        self.photos_dir = Path(self.config.get('photos_dir', '/var/lib/watchpot/photos'))
        self.photos_dir.mkdir(parents=True, exist_ok=True)
        self.error_log_file = '/var/log/watchpot/capture_errors.log'
        
    def load_config(self, config_file):
        """Load configuration from JSON file"""
        try:
            with open(config_file, 'r') as f:
                return json.load(f)
        except FileNotFoundError:
            logger.warning(f"Configuration file {config_file} not found, using default configuration")
            return {
                'photo_width': 1920,
                'photo_height': 1080,
                'photo_quality': 95,
                'photos_dir': '/var/lib/watchpot/photos',
                'max_photos_keep': 50,
                'log_level': 'INFO',
                'send_error_logs': True
            }
        except json.JSONDecodeError as e:
            logger.error(f"Error parsing configuration file: {e}")
            raise
    
    def log_error_for_email(self, error_msg):
        """Log error to separate file for email inclusion"""
        try:
            timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            with open(self.error_log_file, 'a') as f:
                f.write(f"{timestamp} - CAPTURE ERROR: {error_msg}\n")
        except Exception as e:
            logger.error(f"Could not write to error log: {e}")
    
    def capture_photo(self):
        """Capture photo using rpicam-still"""
        timestamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
        filename = f"watchpot_{timestamp}.jpg"
        filepath = self.photos_dir / filename
        
        # rpicam-still command
        cmd = [
            'rpicam-still',
            '-o', str(filepath),
            '--width', str(self.config.get('photo_width', 1920)),
            '--height', str(self.config.get('photo_height', 1080)),
            '--quality', str(self.config.get('photo_quality', 95)),
            '--immediate',  # Immediate capture without preview
            '--nopreview'   # No preview
        ]
        
        try:
            logger.info(f"Capturing photo: {filename}")
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            logger.info(f"Photo captured successfully: {filepath}")
            
            # Verify file was created
            if filepath.exists():
                size = filepath.stat().st_size
                logger.info(f"File size: {size} bytes")
                
                # Clean up old photos if necessary
                self.cleanup_old_photos()
                
                return str(filepath)
            else:
                raise FileNotFoundError(f"File {filepath} was not created")
                
        except subprocess.CalledProcessError as e:
            error_msg = f"Error capturing photo: {e} - STDERR: {e.stderr}"
            logger.error(error_msg)
            self.log_error_for_email(error_msg)
            raise
        except Exception as e:
            error_msg = f"Generic error during capture: {e}"
            logger.error(error_msg)
            self.log_error_for_email(error_msg)
            raise
    
    def cleanup_old_photos(self):
        """Remove oldest photos keeping only the latest N"""
        max_photos = self.config.get('max_photos_keep', 50)
        
        # Get all photos sorted by modification date
        photos = list(self.photos_dir.glob('watchpot_*.jpg'))
        photos.sort(key=lambda x: x.stat().st_mtime, reverse=True)
        
        # Remove oldest photos
        photos_to_remove = photos[max_photos:]
        for photo in photos_to_remove:
            try:
                photo.unlink()
                logger.info(f"Removed old photo: {photo.name}")
            except Exception as e:
                logger.error(f"Error removing photo {photo.name}: {e}")

def main():
    """Main function"""
    try:
        capturer = PhotoCapture()
        photo_path = capturer.capture_photo()
        print(photo_path)  # Output for email script
        return 0
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        return 1

if __name__ == "__main__":
    exit(main())
