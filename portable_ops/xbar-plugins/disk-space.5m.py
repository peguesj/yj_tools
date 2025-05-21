#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import os
import json
from datetime import datetime, timedelta
import subprocess
import matplotlib.pyplot as plt
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
        import matplotlib.pyplot as plt
        return plt
    except ModuleNotFoundError:
        try:
            subprocess.check_call([sys.executable, "-m", "pip", "install", "--user", "matplotlib"])
            import matplotlib.pyplot as plt
            return plt
        except Exception as e:
            log_error(e)
            return None

def main():
    try:
        df_output = subprocess.check_output(['df', '-g', '/']).decode().splitlines()
        available_gb = df_output[1].split()[3] + 'G'
        now = datetime.utcnow()
        now_str = now.strftime(TIME_FORMAT)

        if os.path.exists(LOG_FILE):
            with open(LOG_FILE) as f:
                data = json.load(f)
        else:
            data = {}

        data = {
            k: v for k, v in data.items()
            if datetime.strptime(k, TIME_FORMAT) >= now - MAX_AGE
        }
        data[now_str] = available_gb

        with open(LOG_FILE, 'w') as f:
            json.dump(data, f)

        plt = ensure_matplotlib()
        if plt:
            timestamps = list(data.keys())
            values = [float(v.replace('G', '')) for v in data.values()]
            times = [datetime.strptime(t, TIME_FORMAT) for t in timestamps]

            plt.figure(figsize=(6, 2.5))
            plt.plot(times, values, marker='o', linestyle='-', linewidth=1)
            plt.title("Disk Free (GB) – {}".format(LABEL))
            plt.xticks(rotation=45, ha='right')
            plt.grid(True)
            plt.tight_layout()
            plt.savefig(IMG_FILE)
            plt.close()

        print(f"💾 {available_gb}")
        print("---")
        if plt:
            print("Show Disk History | image=" + IMG_FILE)
        else:
            print("History graph unavailable – matplotlib not found")

    except Exception as e:
        log_error(e)
        print("💾 ERR")
        print("---")
        print("View error log | terminal=false bash='open ~/disklog_error.log'")

if __name__ == "__main__":
    main()
