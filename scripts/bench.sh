#!/bin/bash
# Unattended measurements; raw evidence is retained in a temporary directory.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${LIGHTTTS_BENCH_SKIP_BUILD:-0}" != 1 ]]; then scripts/build-app.sh; fi
exec python3 - "$@" <<'PY'
import os, subprocess, tempfile, time, re, statistics, pathlib
out = pathlib.Path(tempfile.mkdtemp(prefix='lighttts-bench-'))
print('Evidence:', out, flush=True)
def run(args):
    return subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
def pids(path):
    return [int(x) for x in run(['pgrep', '-f', '^' + re.escape(path) + '($| )']).stdout.split() if x.isdigit()]
def terminate(path):
    for pid in pids(path):
        try: os.kill(pid, 15)
        except ProcessLookupError: pass
    deadline = time.monotonic() + 30
    while pids(path) and time.monotonic() < deadline: time.sleep(.2)
    if pids(path): raise RuntimeError('Could not quit ' + path)
def footprint(pid, label):
    result = run(['footprint', str(pid)])
    (out / (label + '-footprint.txt')).write_text(result.stdout)
    match = re.search(r'^\s*phys_footprint:\s*([^\n]+)' , result.stdout, re.I | re.M)
    print(label, 'footprint:', match.group(1).strip() if match else 'N/A (see evidence)', flush=True)
    return bool(match) and result.returncode == 0
def idle(pid, label, path):
    footprint_ok = footprint(pid, label)
    result = run(['top','-l','31','-s','2','-stats','pid,command,cpu,power,idlew,mem'])
    (out / (label + '-top.txt')).write_text(result.stdout)
    rows = []
    for line in result.stdout.splitlines():
        cols = line.split()
        if len(cols) >= 6 and cols[0] == str(pid):
            try: rows.append(tuple(float(x) for x in cols[2:5]))
            except ValueError: pass
    rows = rows[1:]  # first sample is cumulative since launch
    if footprint_ok and len(rows) == 30 and result.returncode == 0 and pids(path) == [pid]:
        print(label, '60s means CPU%, power, idle wakeups/s:', *(round(statistics.mean(x), 2) for x in zip(*rows)), flush=True)
        return True
    print(label, 'top: N/A, complete samples:', len(rows), flush=True)
    return False
def settle(path, label, launch):
    for attempt in range(1, 4):
        terminate(path)
        start = time.monotonic()
        launch(attempt)
        time.sleep(2)
        found = pids(path)
        if len(found) != 1:
            print(label, 'attempt', attempt, 'launch failed or ambiguous:', found, flush=True); continue
        pid = found[0]
        print(label, 'attempt', attempt, 'pid', pid, 'settling 120s', flush=True)
        while time.monotonic() - start < 120 and pids(path) == [pid]: time.sleep(1)
        if pids(path) != [pid]:
            print(label, 'attempt', attempt, 'exited or relaunched during settling', flush=True); continue
        if idle(pid, label, path): return pid
        print(label, 'attempt', attempt, 'collection incomplete; retrying', flush=True)
    print(label, 'idle measurement unavailable after 3 attempts', flush=True)
    return None
superpath = '/Applications/superwhisper.app/Contents/MacOS/superwhisper'
lightpath = os.path.expanduser('~/Applications/LightTTS.app/Contents/MacOS/LightTTS')
lightlog = open(out / 'light-launch.log', 'w')
def lightlaunch(attempt):
    print('lighttts spawn uptime:', time.monotonic(), flush=True)
    subprocess.Popen([lightpath], env=dict(os.environ, LIGHTTTS_TEST_TRACE='1'), stdout=lightlog, stderr=lightlog, start_new_session=True)
def fixture():
    terminate(lightpath)
    aiff, wav = out / 'speech.aiff', out / 'speech.wav'
    if run(['say', '-o', str(aiff), 'This is a local speech recognition test.']).returncode or run(['afconvert', '-f', 'WAVE', '-d', 'LEI16@16000', '-c', '1', str(aiff), str(wav)]).returncode:
        print('Fixture audio generation failed', flush=True); return
    logfile = out / 'fixture.log'
    env = dict(os.environ, LIGHTTTS_TEST_AUDIO=str(wav), LIGHTTTS_TEST_AUTOSTART='1', LIGHTTTS_TEST_AUTOSTOP_SECONDS='9', LIGHTTTS_TEST_MODEL='whisper-tiny.en', LIGHTTTS_TEST_TRACE='1', NSUnbufferedIO='YES')
    with logfile.open('w') as log:
        proc = subprocess.Popen([lightpath], env=env, stdout=log, stderr=log, start_new_session=True)
        start = time.monotonic(); completed = None; peak = 0
        helper = os.path.expanduser('~/Applications/LightTTS.app/Contents/Helpers/LightTTSEngine')
        samples = []
        while time.monotonic() - start < 360 and proc.poll() is None:
            now = time.monotonic()
            data = logfile.read_text(errors='replace')
            if completed is None and 'LIGHTTTS_TEST transcription completed' in data:
                completed = now; print('Fixture completion observed at', round(now-start, 1), 's', flush=True)
            if completed and now - completed >= 150: break
            sizes = []
            for pid in [proc.pid] + pids(helper):
                result = run(['footprint', str(pid)])
                match = re.search(r'^\s*phys_footprint:\s*([0-9.]+)\s*(B|KB|MB|GB)', result.stdout, re.M)
                if match:
                    size = float(match.group(1)) * {'B': 1/1048576, 'KB': 1/1024, 'MB': 1, 'GB': 1024}[match.group(2)]
                    sizes.append(size)
            if sizes:
                peak = max(peak, sum(sizes)); samples.append((round(now-start, 1), sizes))
            time.sleep(2)
        (out / 'fixture-samples.txt').write_text(repr(samples))
        print('Fixture sampled peak total MB:', round(peak, 2), '; completed:', bool(completed), flush=True)
        if completed and time.monotonic() - completed >= 150:
            footprint(proc.pid, 'lighttts-post-transcription')
            print('Helper 150s after completion:', pids(helper) or 'exited', flush=True)
        else: print('Post-transcription footprint: N/A; completion or wait not observed', flush=True)
        terminate(lightpath)
try:
    settle(superpath, 'superwhisper', lambda attempt: run(['open', '-a', 'superwhisper']))
    terminate(superpath)
    settle(lightpath, 'lighttts', lightlaunch)
    fixture()
finally:
    terminate(superpath)
    terminate(lightpath)
    lightlog.close()
print('Launch to menu: LightTTS trace recorded; SuperWhisper N/A without non-prompting menu observation.', flush=True)
print('Transcription and stop-to-paste: N/A unless independently measured.', flush=True)
PY
