#!/usr/bin/env python3
"""Read-only process-tree samples. The operator must verify idle recording state."""
import argparse, json, re, subprocess, time
p = argparse.ArgumentParser()
p.add_argument('--pid', type=int, required=True, help='root app PID')
p.add_argument('--seconds', type=int, default=60)
p.add_argument('--interval', type=float, default=5)
p.add_argument('--idle-confirmed', action='store_true', help='operator verified that recording and processing are stopped')
a = p.parse_args()
if not a.idle_confirmed: p.error('verify app is not recording or processing, then pass --idle-confirmed')
if a.seconds < 0 or a.interval <= 0: p.error('seconds must be nonnegative and interval positive')
def cpu_seconds(value):
    days, clock = value.split('-', 1) if '-' in value else ('0', value)
    parts = [float(part) for part in clock.split(':')]
    seconds = 0
    for part in parts: seconds = seconds * 60 + part
    return int(days) * 86400 + seconds
previous = {}
previous_time = None
end = time.monotonic() + a.seconds
while True:
    output = subprocess.check_output(['ps', '-axo', 'pid=,ppid=,time=,comm='], text=True)
    sampled_at = time.monotonic()
    rows = []
    for line in output.splitlines():
        parts = line.strip().split(None, 3)
        if len(parts) == 4: rows.append((int(parts[0]), int(parts[1]), cpu_seconds(parts[2]), parts[3]))
    if not any(pid == a.pid for pid, _, _, _ in rows): raise SystemExit('root process exited')
    ids = {a.pid}
    while True:
        expanded = ids | {pid for pid, parent, _, _ in rows if parent in ids}
        if expanded == ids: break
        ids = expanded
    tree = [dict(pid=pid, ppid=parent, cpu_seconds=cpu, cpu_percent=(max(0, cpu - previous[pid]) / (sampled_at - previous_time) * 100 if previous_time is not None and pid in previous else None), command=cmd) for pid, parent, cpu, cmd in rows if pid in ids]
    previous = {process['pid']: process['cpu_seconds'] for process in tree}
    previous_time = sampled_at
    neural = []
    try:
        fp = subprocess.check_output(['footprint', '--noCategories'] + [str(pid) for pid in sorted(ids)], stderr=subprocess.STDOUT, text=True)
        match = re.search(r'Summary Footprint:\s*([^\n]+)', fp)
        if not match and len(tree) == 1: match = re.search(r'Footprint:\s*([^\n(]+)', fp)
        footprint = match.group(1).strip() if match else None
        neural = re.findall(r'^\s*(neural(?:_peak)?):\s*([^\n]+)', fp, re.MULTILINE)
    except subprocess.CalledProcessError as e:
        footprint = None
        print(json.dumps({'footprint_error': e.output}))
    cpu = [process['cpu_percent'] for process in tree]
    print(json.dumps(dict(time=time.time(), processes=tree, total_cpu_percent=sum(cpu) if all(value is not None for value in cpu) else None, total_physical_footprint_excluding_neural=footprint, neural_metrics=neural)), flush=True)
    remaining = end - time.monotonic()
    if remaining <= 0: break
    time.sleep(min(a.interval, remaining))
