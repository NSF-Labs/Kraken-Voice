#!/usr/bin/env python3
"""Regenerate a reviewable summary from collected Firebase evidence (no network)."""
import json
from pathlib import Path
from statistics import median

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'spike/hardware_probe/firebase'


def safe(value):
    return str(value).replace('|', '/').replace('\n', ' ')


def main():
    lines = ['# Firebase qualification results', '',
             'Discovery is hardware evidence; short synthetic inference passes are not release certification.', '',
             '## Test matrices', '', '| Matrix | State | Outcome | Results |', '|---|---|---|---|']
    for path in sorted(OUT.glob('matrix-*/matrix.json')):
        data = json.loads(path.read_text())
        url = data.get('resultStorage', {}).get('resultsUrl', '')
        lines.append(f"| {path.parent.name} | {data['state']} | {data.get('outcomeSummary', 'Pending')} | [Console]({url}) |")
    lines += ['', '## Inference observations', '',
              '| Matrix / Firebase device | Actual phone | Model candidate | Backend | Outcome | Load ms | First text ms (median) | Decode tokens/sec (median) | Details |',
              '|---|---|---|---|---|---:|---:|---:|---|']
    for path in sorted(OUT.glob('matrix-*/**/inference-probe/*.json')):
        d = json.loads(path.read_text()); rel = path.relative_to(OUT)
        responses = d.get('responses', [])
        first = [r['firstTextMs'] for r in responses if 'firstTextMs' in r]
        rate = [r['decodeTokensPerSecond'] for r in responses if 'decodeTokensPerSecond' in r]
        detail = d.get('error') or f"{len(responses)} short synthetic summaries; peak memory not measured"
        outcome = 'Inconclusive: model delivery' if d.get('failureStage') in ('download', 'staging') else d.get('status', '?')
        lines.append(f"| {rel.parts[0]} / {rel.parts[1]} | {safe(d.get('model', '?'))} | {safe(d.get('modelCandidate', '?'))} | {d.get('requestedBackend', '?')} | {outcome} | {d.get('loadMs', '—')} | {round(median(first), 1) if first else '—'} | {round(median(rate), 1) if rate else '—'} | {safe(detail)} |")
    lines += ['', '## Interpretation limits', '',
              '- Download failures are inconclusive for inference support. Retries remain separate rows.',
              '- Firebase can allocate different regional variants under the same device ID. Actual model is recorded per run.',
              '- GPU tests explicitly request Backend.GPU; per-operator CPU work is not measured. Native logs provide additional evidence.',
              '- NPU tests use the app Hexagon bridge, which requires HTP0 and rejects CPU-only execution. CPU host/unsupported operations remain.',
              '- Three short summaries do not qualify long appointments, sustained thermals, cancellation or summary quality across real workloads.',
              '- GPU load timing excludes checksum verification; NPU load timing includes the bridge checksum. Do not treat those timings as an identical initialization benchmark.',
              '- Gemma 4 E2B is the only qualification model. Gemma 3 tests are cancelled; devices unable to run Gemma 4 are excluded, with no smaller-model fallback.',
              '- Production device eligibility is unchanged. Existing S26 sustained NPU thermal concerns are not cleared by a smoke test.', '']
    (OUT / 'RESULTS.md').write_text('\n'.join(lines))
    print(OUT / 'RESULTS.md')


if __name__ == '__main__':
    main()
