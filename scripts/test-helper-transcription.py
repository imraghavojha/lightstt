#!/usr/bin/env python3
"""Check a complete generated sentence through the real local helper."""
import json
import os
import pathlib
import re
import struct
import subprocess
import sys
import tempfile
import time
import wave

helper, wav = sys.argv[1:]
model_path = pathlib.Path.home() / 'Library/Application Support/LightTTS/Models/whisper-tiny.en'
if not model_path.is_file():
    print('SKIP: Whisper Tiny EN model is not downloaded')
    sys.exit(0)
with wave.open(wav, 'rb') as source:
    assert (source.getnchannels(), source.getsampwidth(), source.getframerate()) == (1, 2, 16000)
    data = source.readframes(source.getnframes())
    samples = struct.unpack('<' + 'h' * (len(data) // 2), data)
with tempfile.TemporaryDirectory(prefix='lighttts-transcription-') as temp:
    root = pathlib.Path(temp)
    audio = root / 'audio.pcm'
    audio.write_bytes(struct.pack('<' + 'f' * len(samples), *(s / 32768 for s in samples)))
    with subprocess.Popen([helper], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, text=True) as process:
        def request(command):
            reply = root / (str(time.monotonic_ns()) + '.json')
            process.stdin.write(json.dumps(dict(command, reply=str(reply))) + '\n')
            process.stdin.flush()
            deadline = time.monotonic() + 120
            while not reply.exists():
                if process.poll() is not None or time.monotonic() >= deadline:
                    raise RuntimeError('Helper exited or timed out')
                time.sleep(.02)
            result = json.loads(reply.read_text())
            if result.get('error'): raise RuntimeError(result['error'])
            return result
        request(dict(action='warm', model=dict(id='whisper-tiny.en', name='Whisper Tiny EN', engine='whisper')))
        result = request(dict(action='transcribe', audio=str(audio)))
        words = re.findall(r'\w+', result.get('text', '').lower())
        expected = 'the quick brown fox jumps over the lazy dog'.split()
        if not any(words[i:i + len(expected)] == expected for i in range(len(words))):
            raise RuntimeError('Incomplete sentence: ' + repr(result.get('text')))
        print('Whisper Tiny EN: complete sentence passed')
        process.stdin.close()
        process.wait(timeout=10)
