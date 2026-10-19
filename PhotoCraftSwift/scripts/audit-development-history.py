#!/usr/bin/env python3
"""Index the surviving development record; never infer missing historical outcomes.

Run without arguments to refresh docs/DEVELOPMENT_HISTORY.json, or --check to
verify its file hashes, milestone anchors and inventory against the current files.
This is a documentation audit, not a replacement for Swift or live UI testing.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / 'docs/DEVELOPMENT_HISTORY.json'
ROLLING = {'artifacts/full-tests.log', 'artifacts/verification.json',
           'artifacts/photato-release-verification.json', 'artifacts/photato-package-check.json'}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def result(text):
    summaries = re.findall(r'Executed (\d+) tests?, with (\d+) failures?.*?in ([\d.]+)', text)
    started = re.search(r"Test Suite '[^']+' started at ([\d-]+ [\d:.]+)\.", text)
    data = {'embedded_start_time': started[1] if started else None,
            'time_zone': 'not embedded in XCTest line; do not assume UTC'}
    crashed = re.search(r'exited with unexpected signal code (\d+)', text)
    if crashed:
        data.update(outcome='crashed', signal=int(crashed[1]),
                    scope='Test process terminated unexpectedly; preceding suite summaries do not prove run completion')
        if summaries:
            tests, failures, seconds = summaries[-1]
            data['last_reported_summary'] = dict(tests=int(tests), failures=int(failures), seconds=float(seconds))
        return data
    if summaries:
        tests, failures, seconds = summaries[-1]
        data.update(tests=int(tests), failures=int(failures), seconds=float(seconds),
                    outcome='failed' if int(failures) else 'passed',
                    scope='last reported XCTest summary only')
    else:
        data.update(outcome='build_failed' if re.search(r'^error: (?:Build failed|fatalError)', text, re.M)
                    else 'no_xctest_summary',
                    scope='absence of a test summary is not a passing test run')
    return data


def make_report():
    log = (ROOT / 'docs/DEVLOG.md').read_text()
    sections = re.findall(r'<a id="(dev-step-\d{3})"></a>\n\n## ([^\n]+)\n(.*?)(?=\n<a id="dev-step-|\Z)', log, re.S)
    assert sections, 'No development entries found'
    ids = [int(anchor.rsplit('-', 1)[1]) for anchor, _, _ in sections]
    assert len(ids) == len(set(ids)) and sorted(ids) == list(range(1, len(ids) + 1))
    assert len(re.findall(r'^## \d{4}-\d{2}-\d{2} — ', log, re.M)) == len(sections)
    index = re.search(r'<!-- history-index:start -->(.*?)<!-- history-index:end -->', log, re.S)
    assert index, 'Missing chronological navigation'
    linked = re.findall(r'\]\(#(dev-step-\d{3})\)', index[1])
    assert linked == [f'dev-step-{n:03}' for n in sorted(ids)], 'Chronological index differs from entries'
    milestones = []
    missing = []
    for anchor, title, body in sections:
        refs = sorted(set(re.findall(r'`((?:artifacts|docs|scripts|Sources|Tests)/[^`\n]+)`', body)))
        pointers = []
        for ref in refs:
            matches = sorted(ROOT.glob(ref)) if any(c in ref for c in '*?[') else [ROOT / ref]
            present = [str(p.relative_to(ROOT)) for p in matches if p.exists()]
            pointers.append({'reference': ref, 'existing_paths': present,
                             'rolling_current_snapshot': ref in ROLLING})
            if not present:
                missing.append({'entry': anchor, 'reference': ref})
        milestones.append({'id': anchor, 'title': title,
                           'link': f'DEVLOG.md#{anchor}', 'section_sha256': hashlib.sha256(body.encode()).hexdigest(),
                           'references_explicitly_named_in_entry': pointers})
    files = []
    candidates = [ROOT / x for x in ['AGENTS.md', 'README.md', 'CONTRIBUTING.md',
                                   'scripts/audit-development-history.py']]
    candidates += [p for p in (ROOT / 'docs').iterdir() if p.is_file() and p != OUTPUT]
    candidates += [p for p in (ROOT / 'artifacts').rglob('*')
                   if p.is_file() and p.suffix in ('.log', '.json', '.txt')
                   and 'development-history-audit' not in p.parts]
    for p in sorted(set(candidates)):
        relative = str(p.relative_to(ROOT))
        row = {'path': relative, 'sha256': sha(p), 'bytes': p.stat().st_size,
               'rolling_current_snapshot': relative in ROLLING}
        if p.suffix == '.log':
            row['test_result'] = result(p.read_text(errors='replace'))
        files.append(row)
    return {
        'schema_version': 1, 'latest_recorded_date': max(title[:10] for _, title, _ in sections),
        'purpose': 'Trace the surviving record from initial source inspection through the current milestone',
        'limits': [
            'This is an evidence inventory, not a complete keystroke, tool-call or commit history.',
            'The first milestone is retrospectively expanded from surviving records; missing detail stays unknown.',
            'Some early full-suite logs and rolling verification summaries were overwritten. Their old claims are narrative evidence, not independently reverified here.',
            'Dated filenames can also have been reused. Present hashes identify the files now, not every earlier version.',
            'Milestone sequence follows documented dependencies and recorded dates; exact intra-day timing is not inferred.',
            'The Swift subtree has not yet been committed in the enclosing Desktop repository; no initial commit or upstream base revision is invented.',
            'No native application tests or Photoshop interactions are rerun by this audit.',
        ],
        'milestones': sorted(milestones, key=lambda x: x['id']),
        'missing_explicit_references': missing,
        'evidence_files': files,
        'counts': {'milestones': len(milestones), 'evidence_files': len(files),
                   'logs': sum('test_result' in x for x in files),
                   'missing_explicit_references': len(missing)},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    report = make_report()
    if args.check:
        assert not report['missing_explicit_references'], 'Development entries contain missing file references'
        assert json.loads(OUTPUT.read_text()) == report, 'History inventory is stale; preserve it, then refresh it'
    else:
        if OUTPUT.exists():
            prior = OUTPUT.read_bytes()
            if prior != (json.dumps(report, indent=2) + '\n').encode():
                archive = ROOT / 'artifacts/development-history-audit/index-versions'
                archive.mkdir(parents=True, exist_ok=True)
                backup = archive / (hashlib.sha256(prior).hexdigest() + '.json')
                if not backup.exists():
                    backup.write_bytes(prior)
        OUTPUT.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'check': 'passed' if args.check else 'refreshed', **report['counts']}, indent=2))
    if report['missing_explicit_references']:
        print(json.dumps(report['missing_explicit_references'], indent=2))


if __name__ == '__main__':
    main()
