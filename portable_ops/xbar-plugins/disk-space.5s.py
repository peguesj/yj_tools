#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import os
import json
from datetime import datetime, timedelta
import subprocess
import sys
import traceback

LABEL = "Macintosh HD"
LOG_FILE = os.path.expanduser("~/disklog.json")
IMG_FILE = os.path.expanduser("~/diskspace.png")
ERROR_LOG = os.path.expanduser("~/disklog_error.log")
TIME_FORMAT = "%Y-%m-%dT%H:%M:%S"
MAX_AGE = timedelta(days=7)

def log_error(e):
    with open(ERROR_LOG, "a") as f:
        f.write(f"[{datetime.utcnow().isoformat()}] {str(e)}\n")
        f.write(traceback.format_exc())
        f.write("\n\n")

def ensure_matplotlib():
    try:
        import importlib
        plt = importlib.import_module("matplotlib.pyplot")
        return plt
    except ModuleNotFoundError:
        try:
            subprocess.check_call([sys.executable, "-m", "pip", "install", "--user", "matplotlib"])
            import importlib
            plt = importlib.import_module("matplotlib.pyplot")
            return plt
        except Exception as e:
            log_error(e)
            return None

def parse_value(v):
    if v.endswith("TB"):
        return float(v.replace("TB", "")) * 1024
    elif v.endswith("GB"):
        return float(v.replace("GB", ""))
    elif v.endswith("MB"):
        return float(v.replace("MB", "")) / 1024
    else:
        return float(v)

def main():
    try:
        df_output = subprocess.check_output(['df', '-k', '/']).decode().splitlines()
        available_kb = int(df_output[1].split()[3])
        available_mb = available_kb / 1024
        available_gb = available_mb / 1024
        available_tb = available_gb / 1024

        if available_tb >= 1:
            available_str = f"{available_tb:.2f}TB"
        elif available_gb >= 1:
            available_str = f"{available_gb:.2f}GB"
        else:
            available_str = f"{available_mb:.1f}MB"

        now = datetime.utcnow()
        now_str = now.strftime(TIME_FORMAT)

        # Load and filter log data
        if os.path.exists(LOG_FILE):
            with open(LOG_FILE) as f:
                data = json.load(f)
        else:
            data = {}

        # Filter data to only keep entries within MAX_AGE
        data = {k: v for k, v in data.items() if datetime.strptime(k, TIME_FORMAT) >= now - MAX_AGE}
        # Add current value
        data[now_str] = available_str

        with open(LOG_FILE, 'w') as f:
            json.dump(data, f)

        plt = ensure_matplotlib()
        # Get total and used space for percentage calculation
        total_kb = int(df_output[1].split()[1])
        percent_free = available_kb / total_kb * 100

        # Trend character selection
        sorted_timestamps = sorted(data.keys())
        if len(sorted_timestamps) >= 2:
            last_time = sorted_timestamps[-2]
            last_value = parse_value(data[last_time])
            current_value = parse_value(available_str)

            delta = current_value - last_value
            change_pct = abs(delta) / last_value if last_value != 0 else 0

            if delta > 0:
                char = "▲" if change_pct >= 0.25 else "△"
            elif delta < 0:
                char = "▼" if change_pct >= 0.25 else "▽"
            else:
                char = "•"  # no change
        else:
            char = "•"  # insufficient history

        # Color logic only for <5% available
        color = ""
        if percent_free <= 5:
            color = " color=#ff0000"

        # Output available space with emoji and trend
        print(f"💽 {available_str} {char}|{color}")
        print("---")
        if plt:
            timestamps = list(data.keys())
            values = [parse_value(v) for v in data.values()]
            times = [datetime.strptime(t, TIME_FORMAT) for t in timestamps]

            plt.figure(figsize=(6, 2.5))
            plt.plot(times, values, marker='o', linestyle='-', linewidth=1)
            plt.title("Disk Free (GB) – {}".format(LABEL))
            plt.xticks(rotation=45, ha='right')
            plt.grid(True)
            plt.tight_layout()
            plt.savefig(IMG_FILE)
            plt.close()
            print("Show Disk History | image=" + IMG_FILE)
        else:
            print("History graph unavailable – matplotlib not found")

    except Exception as e:
        log_error(e)
        print("🖴 ERR")
        print("---")
        print(f"Error: {str(e)}")
        print("View error log | terminal=false bash='open ~/disklog_error.log'")

if __name__ == "__main__":
    main()
