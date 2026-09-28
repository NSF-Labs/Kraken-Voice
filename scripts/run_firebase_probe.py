#!/usr/bin/env python3
"""Explicit bounded Firebase submission; no billing/quota changes or automatic retries."""
import argparse
import json
import pathlib
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
GROUPS = {
    'gpu-retry': [('m1q', '36'), ('blazer', '36')],
    'npu-retry': [('m1q', '36')],
    'npu': [('m1q', '36'), ('pa3q', '36')],
    'priority': [('m1q', '36'), ('pa3q', '36'), ('e3q', '36')],
    'budget': [('a16x', '36'), ('a16', '35')],
    'coverage': [('dm3q', '34'), ('blazer', '36'), ('caiman', '35'), ('houji', '35')],
}

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--project', required=True)
    p.add_argument('--gcloud', default=shutil.which('gcloud'))
    p.add_argument('--group', choices=GROUPS, required=True)
    p.add_argument('--phase', choices=['discovery', 'gpu', 'npu'], default='discovery')
    p.add_argument('--app-uri', help='Reuse an already uploaded identical app APK (gs:// URI)')
    p.add_argument('--results-bucket', help='Existing Firebase results bucket')
    p.add_argument('--model-source', help='Pinned model file or private gs:// object to stage before the timed test')
    p.add_argument('--model', choices=['gemma4-e2b-gpu', 'gemma4-e2b-portable-gpu'], default='gemma4-e2b-gpu')
    p.add_argument('--submit', action='store_true', help='Without this flag, only validate and print the command.')
    args = p.parse_args()
    if args.app_uri and not args.app_uri.startswith('gs://'):
        p.error('--app-uri must be a gs:// URI')
    if args.phase == 'npu' and args.group not in ('npu', 'npu-retry'):
        p.error('NPU tests require --group npu or npu-retry (S26 and S25 only)')
    if args.model_source:
        if args.phase == 'discovery':
            p.error('Discovery does not use a model')
        if not args.model_source.startswith('gs://') and not pathlib.Path(args.model_source).is_file():
            p.error('--model-source must be an existing file or gs:// URI')
    if not args.gcloud:
        p.error('Provide --gcloud PATH or put gcloud on PATH')
    app = ROOT / 'build/app/outputs/apk/qualification/debug/app-qualification-debug.apk'
    test = ROOT / 'build/app/outputs/apk/androidTest/qualification/debug/app-qualification-debug-androidTest.apk'
    for f in (app, test):
        if not f.is_file():
            p.error(f'Missing {f}; run scripts/build_hardware_probe.sh')
    inventory = json.loads(subprocess.check_output([args.gcloud, 'firebase', 'test', 'android', 'models', 'list', '--project', args.project, '--format=json'], text=True))
    available = {d['id']: d for d in inventory}
    for model, version in GROUPS[args.group]:
        d = available.get(model, {})
        if d.get('form') != 'PHYSICAL' or version not in d.get('supportedVersionIds', []):
            p.error(f'{model} API {version} not in current physical-device inventory')
    test_class = {'discovery': 'HardwareProbeTest', 'gpu': 'InferenceProbeTest', 'npu': 'NpuProbeTest'}[args.phase]
    directory = 'hardware-probe' if args.phase == 'discovery' else 'inference-probe'
    cmd = [args.gcloud, 'firebase', 'test', 'android', 'run', '--project', args.project,
           '--type', 'instrumentation', '--app', args.app_uri or str(app), '--test', str(test),
           '--test-targets', f'class org.krak_en.voice.{test_class}',
           '--timeout', '2m' if args.phase == 'discovery' else '12m',
           '--no-record-video', '--no-performance-metrics',
           '--directories-to-pull', f'/sdcard/Android/data/org.krak_en.voice.qualification/files/{directory}',
           '--results-history-name', f'kraken-{args.phase}', '--async', '--format=json']
    if args.results_bucket:
        cmd += ['--results-bucket', args.results_bucket]
    for model, version in GROUPS[args.group]:
        cmd += ['--device', f'model={model},version={version}']
    if args.phase == 'gpu':
        cmd += ['--environment-variables', f'runInference=true,modelCandidate={args.model}' + (',useStagedModel=true' if args.model_source else '')]
    elif args.phase == 'npu':
        cmd += ['--environment-variables', 'runInference=true' + (',useStagedModel=true' if args.model_source else '')]
    if args.model_source:
        filename = 'gemma4-e2b-w4.gguf' if args.phase == 'npu' else f'{args.model}.litertlm'
        destination = f'/data/local/tmp/{filename}'
        cmd += ['--other-files', f'{destination}={args.model_source}']
    print(shutil.which(args.gcloud) or args.gcloud)
    import shlex
    print(shlex.join(cmd), flush=True)
    if args.submit:
        subprocess.run(cmd, check=True)

if __name__ == '__main__':
    main()
