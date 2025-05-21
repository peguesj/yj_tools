#!/usr/bin/env python3
import sys
import os
import json
import datetime
import logging
from glob import glob
import re

# Setup logger to output syslog-style logs to stdout
logger = logging.getLogger("cyber_protect_monitor")
logger.setLevel(logging.DEBUG)
handler = logging.FileHandler(os.path.expanduser("~/.cyber_protect_monitor.log"))
formatter = logging.Formatter('%(asctime)s %(name)s[%(process)d]: %(levelname)s %(message)s', datefmt='%b %d %H:%M:%S')
handler.setFormatter(formatter)
logger.handlers = []
logger.addHandler(handler)

# Directory where Cyber Protect Monitor stores local JSON-based logs
LOG_DIR = os.path.expanduser(
    os.getenv("CYBER_PROTECT_LOG_PATH", "~/Library/Application Support/Cyber Protect Monitor/Local Storage/leveldb")
)

# Maximum number of recent files to check
MAX_LOG_FILES = 25

def find_start_time():
    expanded_log_dir = os.path.expanduser(
        os.getenv("CYBER_PROTECT_LOG_PATH", "~/Library/Application Support/Cyber Protect Monitor/Local Storage/leveldb")
    )
    logger.info(f"Searching for latest .log file in {expanded_log_dir}")

    if not os.path.isdir(expanded_log_dir):
        logger.warning(f"Log directory does not exist: {expanded_log_dir}")
        return None, None

    try:
        log_candidates = []
        for root, dirs, files in os.walk(expanded_log_dir):
            for name in files:
                if re.fullmatch(r"\d{6}\.log", name):
                    path = os.path.join(root, name)
                    try:
                        log_candidates.append((os.path.getmtime(path), path))
                        logger.debug(f"Found log file: {path}")
                    except OSError as e:
                        logger.error(f"Error accessing file {path}: {e}")
                        continue

        if not log_candidates:
            logger.warning("No valid .log files found")
            return None, None

        latest_log = max(log_candidates, key=lambda x: x[0])[1]
        logger.info(f"Inspecting latest .log file: {latest_log}")

        with open(latest_log, "rb") as f:
            content = f.read()
            logger.debug(f"Read {len(content)} bytes from {latest_log}")

        try:
            text = content.decode("utf-16", errors="ignore")
            logger.debug("Decoded content using UTF-16")
        except UnicodeDecodeError as e:
            logger.error(f"UTF-16 decoding failed: {e}")
            return None, latest_log

        # Look for a JSON block that contains "startTime"
        match = re.search(r'{[^{}]*startTime[^{}]*}', text, re.DOTALL)
        if not match:
            logger.warning("No JSON block containing 'startTime' found")
            return None, latest_log

        try:
            decoded = json.loads(match.group(0))
            logger.debug(f"Decoded JSON (partial): {str(decoded)[:300]}")
        except json.JSONDecodeError as e:
            logger.error(f"JSON decode error: {e}")
            return None, latest_log

        def recursive_search(d):
            if isinstance(d, dict):
                for k, v in d.items():
                    if k == "startTime" and isinstance(v, str):
                        logger.info(f"Found startTime: {v}")
                        return datetime.datetime.fromisoformat(v.replace("Z", "+00:00"))
                    elif isinstance(v, (dict, list)):
                        result = recursive_search(v)
                        if result:
                            return result
            elif isinstance(d, list):
                for item in d:
                    result = recursive_search(item)
                    if result:
                        return result
            return None

        parsed_time = recursive_search(decoded)
        if parsed_time:
            logger.info(f"Parsed backup start time: {parsed_time}")
            return parsed_time, latest_log
        logger.warning("No startTime found in JSON data")
        return None, latest_log

    except Exception as e:
        logger.exception(f"Error reading log file: {e}")
        return None, None

def color_for_days(days):
    logger.debug(f"Calculating color for {days} days since last backup")
    if days > 7:
        return "red"
    elif days < 3:
        return "green"
    return "orange"

def format_output():
    # Only show last backup summary in menu bar
    now = datetime.datetime.now(datetime.timezone.utc)
    backup_time, latest_log = find_start_time()

    if backup_time:
        delta = now - backup_time
        days = delta.days
        color = color_for_days(days)
        summary = f"🛡️ {days}d ago"
    else:
        color = "gray"
        summary = "🛡️ Unknown"

    print(f"{summary} | color={color}")
    print("---")
    try:
        lines = []
        if backup_time:
            delta = now - backup_time
            days = delta.days
            color = color_for_days(days)
            logger.info(f"Last backup was {days} days ago, color: {color}")
            lines.append(f"🛡️ Last Backup: {days}d ago | color={color}")
            lines.append("---")
            lines.append(f"Backup Start Time: {backup_time.strftime('%Y-%m-%d %H:%M:%S %Z')}")
        else:
            logger.warning("Unable to determine last backup time")
            lines.append("🛡️ Last Backup: Unknown | color=gray")
            lines.append("---")
            lines.append("Unable to locate recent backup logs.")
        lines.append("---")
        if backup_time and latest_log:
            lines.append(f"Log File: {os.path.basename(latest_log)}")
            lines.append(f"-- Reveal in Finder | bash='open \"{LOG_DIR}\"' terminal=false")
            lines.append(f"-- Submit Help Request | bash='echo \"todo: help request\"' terminal=false")
        lines.append("---")
        lines.append("Debug Log | bash='open ~/cyber_protect_monitor.log' terminal=false")

        for line in lines:
            print(line)
    except Exception as err:
        logger.exception("Unhandled error in plugin")
        print("🛡️ Last Backup: ERR | color=red")
        print("---")
        print(f"Error: {err}")
        print("Open logs for more detail | bash='open ~/cyber_protect_monitor.log' terminal=false")

if __name__ == "__main__":
    try:
        logger.info("Starting backup delta xbar plugin")
        format_output()
        logger.info("Plugin execution completed successfully")
    except Exception as err:
        logger.exception("Unhandled error in plugin")
        print("🛡️ Last Backup: ERR | color=red")
        print("---")
        print(f"Error: {err}")
        print("Open logs for more detail | bash='open ~/cyber_protect_monitor.log' terminal=false")
