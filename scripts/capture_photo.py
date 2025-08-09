#!/usr/bin/env python3
"""
WatchPot Photo Capture Script
Captures photos at configured times with resilient error handling
"""

import os
import sys
import subprocess
import datetime
import logging
import time
from pathlib import Path

def setup_logging(log_level='INFO'):
    """Setup logging with proper error handling"""
    log_dir = Path('logs')
    log_dir.mkdir(parents=True, exist_ok=True)
    
    level = getattr(logging, log_level.upper(), logging.INFO)
    logging.basicConfig(
        level=level,
        format='%(asctime)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler(log_dir / 'capture.log'),
            logging.StreamHandler()
        ]
    )
    return logging.getLogger(__name__)

def load_config(config_file):
    """Load configuration with defaults"""
    config = {
        'photo_times': '08:00,10:00,12:00,14:00,16:00,18:00',
        'photo_width': '1920',
        'photo_height': '1080',
        'photo_quality': '95',
        'photos_dir': 'photos',
        'retention_days': '7',
        'max_retries': '3',
        'retry_delay': '30',
        'log_level': 'INFO'
    }
    
    try:
        with open(config_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    key = key.strip().lower()
                    value = value.strip().strip('"\'')
                    config[key] = value
    except Exception as e:
        print(f"Warning: Could not load config file {config_file}: {e}")
        print("Using default configuration")
    
    return config

def check_prerequisites():
    """Check if camera and required tools are available"""
    if not subprocess.run(['which', 'rpicam-still'], capture_output=True).returncode == 0:
        print("Error: rpicam-still not found. Install with: sudo apt install camera-apps")
        return False
    return True

def capture_single_photo(config, time_suffix, logger):
    """Capture a single photo with retry logic"""
    max_retries = int(config.get('max_retries', '3'))
    retry_delay = int(config.get('retry_delay', '30'))
    
    for attempt in range(max_retries):
        try:
            # Create directory structure
            photos_dir = Path(config['photos_dir'])
            photos_dir.mkdir(parents=True, exist_ok=True)
            
            today = datetime.date.today()
            daily_dir = photos_dir / f"daily_{today.strftime('%Y%m%d')}"
            daily_dir.mkdir(exist_ok=True)
            
            # Generate filename
            filename = f"watchpot_{today.strftime('%Y%m%d')}_{time_suffix}.jpg"
            photo_path = daily_dir / filename
            
            # Build capture command
            cmd = [
                'rpicam-still',
                '-o', str(photo_path),
                '--width', config['photo_width'],
                '--height', config['photo_height'],
                '--quality', config['photo_quality'],
                '--immediate',
                '--nopreview',
                '--timeout', '10000'
            ]
            
            logger.info(f"Attempt {attempt + 1}/{max_retries}: Capturing {filename}")
            
            # Execute capture with timeout
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
            
            if result.returncode == 0:
                if photo_path.exists() and photo_path.stat().st_size > 1024:
                    file_size = photo_path.stat().st_size
                    logger.info(f"Photo captured successfully: {filename} ({file_size} bytes)")
                    return str(photo_path)
                else:
                    logger.warning(f"Photo file is empty or too small: {filename}")
                    if photo_path.exists():
                        photo_path.unlink()
            else:
                logger.warning(f"rpicam-still failed (attempt {attempt + 1}): {result.stderr}")
            
            if attempt < max_retries - 1:
                logger.info(f"Retrying in {retry_delay} seconds...")
                time.sleep(retry_delay)
                
        except subprocess.TimeoutExpired:
            logger.warning(f"Photo capture timed out (attempt {attempt + 1})")
        except Exception as e:
            logger.warning(f"Error during capture attempt {attempt + 1}: {e}")
            
        if attempt < max_retries - 1:
            time.sleep(retry_delay)
    
    logger.error(f"Failed to capture photo after {max_retries} attempts")
    return None

def cleanup_old_photos(config, logger):
    """Remove old photos based on retention policy"""
    try:
        retention_days = int(config.get('retention_days', '7'))
        photos_dir = Path(config['photos_dir'])
        
        if not photos_dir.exists():
            return
        
        cutoff_date = datetime.date.today() - datetime.timedelta(days=retention_days)
        
        for daily_dir in photos_dir.glob("daily_*"):
            try:
                dir_date_str = daily_dir.name.replace('daily_', '')
                dir_date = datetime.datetime.strptime(dir_date_str, '%Y%m%d').date()
                
                if dir_date < cutoff_date:
                    logger.info(f"Removing old photo directory: {daily_dir}")
                    import shutil
                    shutil.rmtree(daily_dir)
                    
            except ValueError:
                continue
                
    except Exception as e:
        logger.error(f"Error during cleanup: {e}")

def get_today_photos(config):
    """Get list of all photos captured today"""
    today = datetime.date.today()
    photos_dir = Path(config['photos_dir'])
    daily_dir = photos_dir / f"daily_{today.strftime('%Y%m%d')}"
    
    if not daily_dir.exists():
        return []
    
    photos = list(daily_dir.glob("*.jpg"))
    photos.sort()
    return [str(p) for p in photos]

def should_capture_now(config):
    """Check if we should capture a photo now based on schedule"""
    photo_times = config.get('photo_times', '').split(',')
    current_dt = datetime.datetime.now()
    
    # Allow 5 minutes window for each scheduled time
    for scheduled_time in photo_times:
        scheduled_time = scheduled_time.strip()
        if not scheduled_time:
            continue
            
        try:
            hour, minute = map(int, scheduled_time.split(':'))
            scheduled_dt = current_dt.replace(hour=hour, minute=minute, second=0, microsecond=0)
            
            # Check if current time is within 5 minutes of scheduled time
            time_diff = abs((current_dt - scheduled_dt).total_seconds())
            if time_diff <= 300:  # 5 minutes
                return scheduled_time.replace(':', '')
                
        except ValueError:
            continue
    
    return None

def main():
    import argparse
    
    parser = argparse.ArgumentParser(description='WatchPot Photo Capture')
    parser.add_argument('--config', default='config/watchpot.conf', help='Configuration file')
    parser.add_argument('--time', help='Specific time suffix for manual capture (HHMM format)')
    parser.add_argument('--force', action='store_true', help='Force capture regardless of schedule')
    parser.add_argument('--cleanup', action='store_true', help='Only run cleanup')
    parser.add_argument('--list', action='store_true', help='List today\'s photos')
    
    args = parser.parse_args()
    
    # Load configuration
    config = load_config(args.config)
    logger = setup_logging(config.get('log_level', 'INFO'))
    
    # Handle different modes
    if args.cleanup:
        logger.info("Running photo cleanup")
        cleanup_old_photos(config, logger)
        return
    
    if args.list:
        photos = get_today_photos(config)
        if photos:
            print(f"Photos for today ({len(photos)}):")
            for photo in photos:
                print(f"  {photo}")
        else:
            print("No photos found for today")
        return
    
    # Check prerequisites
    if not check_prerequisites():
        sys.exit(1)
    
    # Determine time suffix
    time_suffix = None
    
    if args.time:
        time_suffix = args.time
    elif args.force:
        time_suffix = datetime.datetime.now().strftime('%H%M')
    else:
        time_suffix = should_capture_now(config)
        if not time_suffix:
            logger.info("Not scheduled to capture photo now")
            return
    
    logger.info(f"Starting photo capture for time: {time_suffix}")
    
    # Capture photo
    photo_path = capture_single_photo(config, time_suffix, logger)
    
    if photo_path:
        logger.info("Photo capture completed successfully")
        
        # Run cleanup occasionally
        if datetime.datetime.now().hour == 1:  # Run cleanup at 1 AM
            cleanup_old_photos(config, logger)
        
        print(f"SUCCESS: {photo_path}")
        sys.exit(0)
    else:
        logger.error("Photo capture failed")
        sys.exit(1)

if __name__ == "__main__":
    main()
