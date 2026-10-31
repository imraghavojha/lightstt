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
end = time.monotonic() + a.seconds
while True:
    output = subprocess.check_output(['ps', '-axo', 'pid=,ppid=,%cpu=,comm='], text=True)
    rows = []
    for line in output.splitlines():
        parts = line.strip().split(None, 3)
        if len(parts) == 4: rows.append((int(parts[0]), int(parts[1]), float(parts[2]), parts[3]))
    ids = {a.pid}
    while True:
        expanded = ids | {pid for pid, parent, _, _ in rows if parent in ids}
        if expanded == ids: break
        ids = expanded
    tree = [dict(pid=pid, ppid=parent, cpu_percent=cpu, command=cmd) for pid, parent, cpu, cmd in rows if pid in ids]
    if not tree: raise SystemExit('root process exited')
    try:
        fp = subprocess.check_output(['footprint', '--noCategories'] + [str(pid) for pid in sorted(ids)], stderr=subprocess.STDOUT, text=True)
        match = re.search(r'Summary Footprint:\s*([^\n]+)', fp)
        if not match and len(tree) == 1: match = re.search(r'Footprint:\s*([^\n(]+)', fp)
        footprint = match.group(1).strip() if match else None
    except subprocess.CalledProcessError as e:
        footprint = None
        print(json.dumps({'footprint_error': e.output}))
    print(json.dumps(dict(time=time.time(), processes=tree, total_cpu_percent=sum(x['cpu_percent'] for x in tree), total_physical_footprint=footprint)), flush=True)
    remaining = end - time.monotonic()
    if remaining <= 0: break
    time.sleep(min(a.interval, remaining))
