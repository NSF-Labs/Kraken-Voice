#!/usr/bin/env python3
"""Read a Firebase matrix and optionally collect JSON reports and native logs."""
import argparse
import json
import pathlib
import shutil
import ssl
import subprocess
import urllib.request


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--project', required=True)
    p.add_argument('--matrix', required=True)
    p.add_argument('--gcloud', default=shutil.which('gcloud'))
    p.add_argument('--output', type=pathlib.Path, default=pathlib.Path('spike/hardware_probe/firebase'))
    p.add_argument('--collect', action='store_true')
    p.add_argument('--logs', action='store_true', help='Also collect potentially large native logs')
    a = p.parse_args()
    if not a.gcloud:
        p.error('Provide --gcloud PATH')
    token = subprocess.check_output([a.gcloud, 'auth', 'print-access-token'], text=True).strip()
    request = urllib.request.Request(
        f'https://testing.googleapis.com/v1/projects/{a.project}/testMatrices/{a.matrix}',
        headers={'Authorization': 'Bearer ' + token})
    ca = pathlib.Path('/etc/ssl/cert.pem')
    context = ssl.create_default_context(cafile=str(ca) if ca.exists() else None)
    with urllib.request.urlopen(request, context=context, timeout=30) as response:
        data = json.load(response)
    out = a.output / a.matrix
    out.mkdir(parents=True, exist_ok=True)
    (out / 'matrix.json').write_text(json.dumps(data, indent=2) + '\n')
    print(a.matrix, data['state'], data.get('outcomeSummary', ''))
    for execution in data.get('testExecutions', []):
        print(execution.get('environment', {}).get('androidDevice', {}), execution.get('state'))
    storage = data.get('resultStorage', {})
    print(storage.get('resultsUrl', ''))
    if a.collect:
        root = storage.get('googleCloudStorage', {}).get('gcsPath')
        if not root:
            p.error('Matrix has no result storage')
        listing = subprocess.check_output([a.gcloud, 'storage', 'ls', '--recursive', root], text=True)
        for uri in sorted(listing.splitlines(), key=lambda item: not item.endswith('.json')):
            if not uri.startswith(root):
                continue
            relative = uri[len(root):].lstrip('/')
            if not (uri.endswith('/hardware.json') or uri.endswith('/gemma4-e2b-gpu.json')
                    or uri.endswith('/gemma4-e2b-portable-gpu.json') or uri.endswith('/gemma4-e2b-npu.json') or (a.logs and uri.endswith('/logcat'))
                    or uri.endswith('/test_result_1.xml')):
                continue
            path = out / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run([a.gcloud, 'storage', 'cp', uri, str(path)], check=True, capture_output=True)
            print('Saved', path)

if __name__ == '__main__':
    main()
