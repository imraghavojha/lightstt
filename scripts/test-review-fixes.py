#!/usr/bin/env python3
"""Run after a release build; uses a local fixture and no model downloads."""
import http.server, json, pathlib, shutil, socketserver, subprocess, sys, tempfile, threading, time

root = pathlib.Path(__file__).resolve().parent.parent
bin_dir = pathlib.Path(subprocess.check_output(['swift', 'build', '-c', 'release', '--show-bin-path'], cwd=root, text=True).strip())
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(b'corrupt')
    def log_message(self, *args): pass
with socketserver.TCPServer(('127.0.0.1', 0), Handler) as server:
    threading.Thread(target=server.serve_forever, daemon=True).start()
    subprocess.run([str(bin_dir / 'model-validation'), '--custom-integrity', f'http://127.0.0.1:{server.server_address[1]}/weights'], check=True)
    server.shutdown()
with tempfile.TemporaryDirectory() as temp:
    temp = pathlib.Path(temp)
    shutil.copy(bin_dir / 'lighttts-cli', temp / 'lighttts-cli')
    for framework in bin_dir.glob('*.framework'):
        shutil.copytree(framework, temp / framework.name, symlinks=True)
    for bundle in bin_dir.glob('*.bundle'):
        shutil.copytree(bundle, temp / bundle.name, symlinks=True)
    helper = temp / 'LightTTSEngine'
    marker = temp / 'called'
    helper.write_text('#!/bin/sh\nprintf "%s" "$1" > "' + str(marker) + '"\n')
    helper.chmod(0o755)
    for args in (['download', 'parakeet-v3'], ['download-parakeet-v3']):
        subprocess.run([str(temp / 'lighttts-cli'), *args], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        assert marker.read_text() == 'download-model'
        marker.unlink()
    print('CLI sibling helper lookup passed')
    # Invalid language must reach each backend's own validator over the warm IPC.
    for model in ({'id':'test', 'name':'test', 'engine':'canary'}, {'id':'test', 'name':'test', 'engine':'sherpa', 'version':'nemo_canary'}):
        if model['engine'] == 'sherpa':
            model['id'] = 'onnx-canary-180m'  # resolved below from the catalog
            catalog = json.loads((root / 'Sources/LightTTSCore/Resources/models.json').read_text())
            model = next(m for m in catalog if m.get('version') == 'nemo_canary')
            path = pathlib.Path.home() / 'Library/Application Support/LightTTS/Models' / model['id']
            if not path.exists():
                print('SKIP ONNX Canary language check: model not installed'); continue
        reply = temp / 'reply.json'
        proc = subprocess.Popen([str(bin_dir / 'LightTTSEngine')], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, text=True)
        try:
            proc.stdin.write(json.dumps({'action':'warm','reply':str(reply),'model':model,'language':'invalid'})+'\n'); proc.stdin.flush()
            for _ in range(500):
                if reply.exists(): break
                time.sleep(.02)
            result = json.loads(reply.read_text())
            assert ('language' in result.get('error', '').lower() or 'supports English, Spanish' in result.get('error', '')), result
            reply.unlink()
        finally:
            proc.terminate(); proc.wait(timeout=5)
    print('Canary helper language validation passed')
