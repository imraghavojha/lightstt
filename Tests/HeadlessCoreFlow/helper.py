#!/usr/bin/env python3
"""Test the real helper protocol with a local model; no model download or app launch."""
import json
import pathlib
import re
import subprocess
import sys
import tempfile
import time

helper, pcm = sys.argv[1:]
model = {'id': 'whisper-tiny.en', 'name': 'Whisper Tiny English', 'engine': 'whisper'}
with tempfile.TemporaryDirectory(prefix='lighttts-helper-') as temp:
    with subprocess.Popen([helper], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, text=True) as proc:
        def request(action, **kwargs):
            reply = pathlib.Path(temp) / (str(time.monotonic_ns()) + '.json')
            proc.stdin.write(json.dumps(dict(action=action, reply=str(reply), **kwargs)) + '\n')
            proc.stdin.flush()
            deadline = time.monotonic() + 30
            while not reply.exists():
                if proc.poll() is not None:
                    raise RuntimeError(f'helper {action} exited unexpectedly')
                if time.monotonic() >= deadline:
                    proc.kill()
                    raise RuntimeError(f'helper {action} timed out')
                time.sleep(0.005)
            result = json.loads(reply.read_text())
            if result.get('error'):
                raise RuntimeError(f'helper {action}: {result["error"]}')
            return result.get('text', '')
        request('warm', model=model)
        request('transcribe', audio=pcm)  # Prime inference before timing.
        start = time.monotonic()
        transcript = request('transcribe', audio=pcm)
        elapsed_ms = (time.monotonic() - start) * 1000
        print(f'Helper warm transcription: {elapsed_ms:.1f} ms; transcript: {transcript!r}', flush=True)
        words = re.findall(r'[a-z]+', transcript.lower())
        expected = 'the quick brown fox jumps over the lazy dog'.split()
        if not any(words[i:i + len(expected)] == expected for i in range(len(words))):
            raise RuntimeError('transcript does not contain the complete sentence')
        if re.search(r'\[[^\]]+\]', transcript):
            raise RuntimeError('transcript contains bracketed annotations')
        limit = float(__import__('os').environ.get('LIGHTTTS_TEST_MAX_LATENCY_MS', '400'))
        if elapsed_ms > limit:
            raise RuntimeError(f'warm transcription exceeded {limit:.0f} ms')
        print('PASS: helper transcript and warm latency guard', flush=True)
        proc.stdin.close()
        proc.wait(timeout=10)
        if proc.returncode:
            raise RuntimeError('helper exited with an error')
