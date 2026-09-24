#!/usr/bin/env python3
"""Run internal qualification on a local, streamed or virtual ADB device.

The internal APK and selected model must already be installed/staged.
Only the separate qualification package is restarted; user app data is untouched.
"""
import argparse
import datetime
import json
from pathlib import Path
import shutil
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--serial', required=True)
parser.add_argument('--mode', choices=['compatibility', 'quick', 'stress'], default='quick')
parser.add_argument('--backend', choices=['GPU', 'NPU'])
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
adb = shutil.which('adb') or str(Path.home() / 'Library/Android/sdk/platform-tools/adb')
base = [adb, '-s', args.serial]
package = 'org.krak_en.voice.qualification'
report_path = f'/sdcard/Android/data/{package}/files/qualification/latest.json'
def run(*command, check=True):
    return subprocess.run(base + list(command), capture_output=True, text=True, check=check, timeout=30)

# Use the phone's clock when filtering stale reports; cloud clocks may differ.
phone_seconds = int(run('shell', 'date', '+%s').stdout.strip())
command = ['shell', 'am', 'start', '-S', '-n', f'{package}/org.krak_en.voice.MainActivity',
           '--es', 'qualification_test', args.mode]
if args.backend:
    command += ['--es', 'qualification_backend', args.backend]
run(*command)
deadline = time.monotonic() + (1000 if args.mode == 'stress' else 360)
last_stage = None
while time.monotonic() < deadline:
    value = run('shell', 'cat', report_path, check=False)
    try:
        report = json.loads(value.stdout)
        started = datetime.datetime.fromisoformat(report['startedUtc'].replace('Z', '+00:00')).timestamp()
        if started < phone_seconds:
            time.sleep(2)
            continue
    except (ValueError, KeyError):
        time.sleep(2)
        continue
    stage = report.get('stage')
    if stage != last_stage:
        print(f'{args.serial}: {stage}', flush=True)
        last_stage = stage
    if report.get('status') != 'running':
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + '\n')
        print(f"{args.serial}: {report['status']} — {args.output}", flush=True)
        raise SystemExit(0 if report['status'] == 'passed' else 1)
    time.sleep(2)
run('shell', 'am', 'force-stop', package)
raise SystemExit('Timed out; qualification app stopped. Saved checkpoint is incomplete, not a pass.')
