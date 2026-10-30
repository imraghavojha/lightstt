#!/usr/bin/env python3
"""Exercise cloud request encoding through the debug helper without network access."""
import json
import os
import pathlib
import select
import struct
import subprocess
import sys
import tempfile
import time
import wave

if len(sys.argv) != 3:
    raise SystemExit('Usage: test-helper-cloud.py DEBUG_HELPER PCM16_MONO_16KHZ_WAV')
helper, wav = sys.argv[1:]
with wave.open(wav, 'rb') as source:
    if (source.getnchannels(), source.getsampwidth(), source.getframerate()) != (1, 2, 16000):
        raise SystemExit('WAV must be mono PCM16 at 16 kHz')
    data = source.readframes(source.getnframes())
    samples = struct.unpack('<' + 'h' * (len(data) // 2), data)
with tempfile.TemporaryDirectory(prefix='lighttts-cloud-test-') as temp:
    root = pathlib.Path(temp)
    audio = root / 'audio.pcm'
    audio.write_bytes(struct.pack('<' + 'f' * len(samples), *(s / 32768 for s in samples)))
    env = dict(os.environ, LIGHTTTS_MOCK_CLOUD='1')
    read_fd, write_fd = os.pipe()
    env["LIGHTTTS_REPLY_FD"] = str(write_fd)
    with os.fdopen(read_fd) as replies, subprocess.Popen([helper], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, pass_fds=(write_fd,), env=env, text=True) as process:
        os.close(write_fd)
        def request(command):
            command['id'] = str(time.monotonic_ns())
            process.stdin.write(json.dumps(command) + '\n')
            process.stdin.flush()
            if not select.select([replies], [], [], 60)[0]:
                raise RuntimeError('Helper timed out')
            line = replies.readline()
            if not line: raise RuntimeError('Helper exited')
            result = json.loads(line)
            assert result['id'] == command['id']
            return result
        for provider, name in [('groq', 'whisper-large-v3'), ('gemini', 'gemini-3.8-flash'), ('elevenlabs', 'scribe_v2'), ('compatible', 'example-model')]:
            model = dict(id='mock-' + provider, name='mock', engine='cloud', cloudProvider=provider, cloudModel=name)
            if provider == 'compatible': model['cloudEndpoint'] = 'https://example.invalid/v1'
            result = request(dict(action='warm', model=model))
            if result.get('error'): raise RuntimeError(provider + ' warm: ' + result['error'])
            result = request(dict(action='transcribe', audio=str(audio)))
            if result.get('text') != 'ok': raise RuntimeError(provider + ' transcription: ' + str(result))
            print(provider + ': helper request and response passed', flush=True)
        process.stdin.close()
        process.wait(timeout=10)
        if process.returncode: raise RuntimeError('Helper exited with error')
