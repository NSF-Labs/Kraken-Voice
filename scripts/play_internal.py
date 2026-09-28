#!/usr/bin/env python3
"""Upload a verified release bundle to this app's Internal testing track only."""
import argparse
import hashlib
import json
import re
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = 'org.krak_en.voice'
API = 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/' + PACKAGE
UPLOAD = 'https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/' + PACKAGE
SCOPE = 'https://www.googleapis.com/auth/androidpublisher'


def call(session, method, url, **kwargs):
    response = session.request(method, url, timeout=300, **kwargs)
    if not response.ok:
        # Do not print credential-bearing headers or full request/response dumps.
        try:
            message = response.json().get('error', {}).get('message', 'Request failed')
        except ValueError:
            message = 'Request failed'
        raise RuntimeError(f'Google Play HTTP {response.status_code}: {message}')
    return response.json() if response.content else {}


def publish(session, bundle, version, name, notes):
    edit = call(session, 'POST', API + '/edits', json={})['id']
    base = API + '/edits/' + edit
    commit_started = False
    try:
        used = []
        for kind in ('bundles', 'apks'):
            used.extend(int(item['versionCode']) for item in
                        call(session, 'GET', base + '/' + kind).get(kind, []))
        if used and version <= max(used):
            raise RuntimeError(f'Build {version} is not newer than Play build {max(used)}. '
                               'Update the matching Dart/native build identities and rebuild.')
        with bundle.open('rb') as stream:
            uploaded = call(session, 'POST', UPLOAD + '/edits/' + edit + '/bundles?uploadType=media',
                            data=stream, headers={'Content-Type': 'application/octet-stream'})
        if int(uploaded['versionCode']) != version:
            raise RuntimeError('Uploaded bundle version does not match the requested release')
        if uploaded.get('sha256') != hashlib.sha256(bundle.read_bytes()).hexdigest():
            raise RuntimeError('Google Play bundle checksum does not match the local artifact')
        release = {'name': name, 'versionCodes': [str(version)], 'status': 'completed',
                   'releaseNotes': [{'language': 'en-US', 'text': notes}]}
        call(session, 'PUT', base + '/tracks/internal',
             json={'track': 'internal', 'releases': [release]})
        call(session, 'POST', base + ':validate')
        commit_started = True
        call(session, 'POST', base + ':commit')
        return {'package': PACKAGE, 'track': 'internal', 'versionCode': version,
                'editId': edit, 'status': 'committed', 'sha256': uploaded['sha256']}
    except Exception:
        if commit_started:
            print(f'Commit outcome needs checking in Play Console (edit {edit}); do not blindly retry.',
                  file=sys.stderr)
        else:
            try:
                call(session, 'DELETE', base)
            except Exception:
                print(f'Could not discard pending edit {edit}; inspect Play Console.', file=sys.stderr)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path, default=ROOT / 'build/app/outputs/bundle/prodRelease/app-prod-release.aab')
    parser.add_argument('--notes-file', type=Path, required=True)
    parser.add_argument('--credentials', type=Path, help='Service-account JSON path; otherwise use local configuration or Application Default Credentials')
    parser.add_argument('--upload', action='store_true', help='Commit a release to Internal testing; otherwise verify locally only')
    args = parser.parse_args()
    version_name, version = re.search(r'^version:\s*([^+\s]+)\+(\d+)',
                                      (ROOT / 'pubspec.yaml').read_text(), re.M).groups()
    bundle = args.bundle.resolve()
    with zipfile.ZipFile(bundle) as archive:
        names = archive.namelist()
        if not any(n.startswith('META-INF/') and n.endswith(('.RSA', '.EC', '.DSA')) for n in names):
            raise RuntimeError('Bundle has no signing certificate; configure the existing Play upload key')
    subprocess.run(['jarsigner', '-verify', str(bundle)], check=True, stdout=subprocess.DEVNULL)
    subprocess.run([sys.executable, str(ROOT / 'scripts/verify_unified_artifact.py'), str(bundle)], check=True)
    notes = args.notes_file.read_text().strip()
    if not notes or len(notes) > 500:
        raise RuntimeError('English release notes must contain 1–500 characters')
    print(json.dumps({'package': PACKAGE, 'track': 'internal', 'versionCode': int(version),
                      'bundle': str(bundle), 'sha256': hashlib.sha256(bundle.read_bytes()).hexdigest()}, indent=2))
    if not args.upload:
        print('Local verification only. Add --upload to publish to Internal testing.')
        return
    import google.auth
    from google.auth.transport.requests import AuthorizedSession
    credentials_path = args.credentials
    local_config = ROOT / '.secrets/play-upload.json'
    if credentials_path is None and local_config.is_file():
        credentials_path = Path(json.loads(local_config.read_text())['credentialsPath'])
    if credentials_path is None:
        credentials, _ = google.auth.default(scopes=[SCOPE])
    else:
        credentials, _ = google.auth.load_credentials_from_file(str(credentials_path), scopes=[SCOPE])
    with AuthorizedSession(credentials) as session:
        result = publish(session, bundle, int(version), version_name, notes)
    receipt = ROOT / 'build/play-internal-receipt.json'
    receipt.write_text(json.dumps(result, indent=2) + '\n')
    print(f'Internal testing edit committed. Receipt: {receipt}. Check Play Console for processing/review status.')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(f'Upload stopped: {error}', file=sys.stderr)
        sys.exit(1)
