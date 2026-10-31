#!/usr/bin/env python3
"""Measure warm helper round trips on one immutable PCM WAV; no GUI or microphone."""
import argparse, hashlib, json, os, pathlib, select, struct, subprocess, tempfile, time, wave

p = argparse.ArgumentParser()
p.add_argument('helper'); p.add_argument('wav'); p.add_argument('--model-id', default='parakeet-v3')
p.add_argument('--runs', type=int, default=5)
a = p.parse_args()
model = next(m for m in json.loads(pathlib.Path('Sources/LightTTSCore/Resources/models.json').read_text()) if m['id'] == a.model_id)
wav = pathlib.Path(a.wav)
print('fixture_sha256', hashlib.sha256(wav.read_bytes()).hexdigest(), 'model', a.model_id)
with wave.open(str(wav), 'rb') as f:
    if (f.getnchannels(), f.getsampwidth(), f.getframerate()) != (1, 2, 16000): raise SystemExit('Expected 16 kHz mono PCM16 WAV')
    pcm = f.readframes(f.getnframes())
samples = struct.unpack('<' + 'h' * (len(pcm) // 2), pcm)
with tempfile.TemporaryDirectory(prefix='lighttts-perf-') as tmp:
    audio = pathlib.Path(tmp) / 'fixture.pcm'
    audio.write_bytes(struct.pack('<' + 'f' * len(samples), *(s / 32768 for s in samples)))
    read_fd, write_fd = os.pipe()
    with os.fdopen(read_fd) as replies, subprocess.Popen([a.helper], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, pass_fds=(write_fd,), env=dict(os.environ, LIGHTTTS_REPLY_FD=str(write_fd)), text=True) as proc:
        os.close(write_fd)
        def request(command):
            command['id'] = str(time.monotonic_ns()); start = time.monotonic_ns()
            proc.stdin.write(json.dumps(command) + '\n'); proc.stdin.flush()
            if not select.select([replies], [], [], 180)[0]: raise RuntimeError('helper timed out')
            line = replies.readline()
            if not line: raise RuntimeError('helper exited')
            result = json.loads(line)
            if result['id'] != command['id'] or result.get('error'): raise RuntimeError(str(result))
            return (time.monotonic_ns() - start) / 1e6, result.get('text')
        print('warm_ms', request(dict(action='warm', model=model))[0])
        for i in range(a.runs):
            ms, text = request(dict(action='transcribe', audio=str(audio)))
            print(json.dumps(dict(run=i+1, helper_roundtrip_ms=round(ms, 3), text=text)))
        proc.stdin.close(); proc.wait(timeout=10)
