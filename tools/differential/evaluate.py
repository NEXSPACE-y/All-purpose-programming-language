"""Strict process-level comparison of official PHP and the independent ALL candidate.

This is a new measurement, not a replacement for historical PHPT/fixture results.
No trimming, newline conversion, diagnostic rewriting, or inferred exit codes.
Python standard library only. Each report records exact inputs and binary hashes.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run_process(argv: list[str], cwd: Path, timeout: float) -> dict:
    started = time.monotonic()
    try:
        proc = subprocess.run(
            argv, cwd=cwd, stdin=subprocess.DEVNULL, capture_output=True,
            timeout=timeout, creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0,
        )
        out, err, code, state = proc.stdout, proc.stderr, proc.returncode, 'EXITED'
    except subprocess.TimeoutExpired as exc:
        out, err, code, state = exc.stdout or b'', exc.stderr or b'', None, 'TIMEOUT'
    return {
        'state': state, 'exit_code': code, 'elapsed_seconds': time.monotonic() - started,
        'stdout_base64': base64.b64encode(out).decode('ascii'),
        'stderr_base64': base64.b64encode(err).decode('ascii'),
        'stdout_utf8_preview': out[:8192].decode('utf-8', errors='backslashreplace'),
        'stderr_utf8_preview': err[:8192].decode('utf-8', errors='backslashreplace'),
        'command': argv,
    }


def differences(oracle: dict, candidate: dict) -> list[str]:
    result = []
    if oracle['state'] != 'EXITED' or candidate['state'] != 'EXITED':
        result.append('process_state')
    for field in ('exit_code', 'stdout_base64', 'stderr_base64'):
        if oracle[field] != candidate[field]:
            result.append(field)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--php', type=Path, required=True)
    parser.add_argument('--powershell', type=Path, required=True)
    parser.add_argument('--adapter', type=Path, required=True)
    parser.add_argument('--cases', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--timeout', type=float, default=30)
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error('--timeout must be positive')
    args.output = args.output.resolve()
    if args.output.exists():
        parser.error('output directory already exists; choose a new run directory')
    for name in ('php', 'powershell', 'adapter', 'cases'):
        path = getattr(args, name).resolve(strict=True)
        if not path.is_file():
            parser.error(f'{name} is not a file')
        setattr(args, name, path)
    worker = Path(__file__).with_name('PhpCandidateWorker.ps1').resolve(strict=True)
    cases = json.loads(args.cases.read_text(encoding='utf-8-sig'))
    ids = [item['id'] for item in cases]
    if len(ids) != len(set(ids)) or not ids:
        parser.error('case IDs must be nonempty and unique')
    before = {name: sha256(getattr(args, name)) for name in ('php', 'powershell', 'adapter', 'cases')}
    before['worker'] = sha256(worker)
    args.output.mkdir(parents=True)
    rows = []
    for index, case in enumerate(cases):
        source = args.output / f'case-{index:04d}.php'
        source.write_bytes(case['code'].encode('utf-8'))
        oracle = run_process([
            str(args.php), '-n', '-d', 'display_errors=stderr', '-d', 'error_reporting=-1',
            '-d', 'date.timezone=UTC', str(source),
        ], args.output, args.timeout)
        candidate = run_process([
            str(args.powershell), '-NoLogo', '-NoProfile', '-NonInteractive',
            '-ExecutionPolicy', 'Bypass', '-File', str(worker),
            '-AdapterPath', str(args.adapter), '-SourcePath', str(source),
        ], args.output, args.timeout)
        diff = differences(oracle, candidate)
        row = {
            'id': case['id'], 'source_sha256': sha256(source), 'source_path': str(source),
            'verdict': 'PASS' if not diff else 'DIFFERENT', 'differences': diff,
            'oracle': oracle, 'candidate': candidate,
        }
        rows.append(row)
        print(f"{row['verdict']}: {case['id']} ({', '.join(diff)})", flush=True)
    after = {name: sha256(getattr(args, name)) for name in ('php', 'powershell', 'adapter', 'cases')}
    after['worker'] = sha256(worker)
    passed = sum(row['verdict'] == 'PASS' for row in rows)
    report = {
        'schema_version': 1, 'status': 'NOT_COMPLETE',
        'measurement': 'exact stdout bytes, stderr bytes, process exit code; no normalization',
        'scope': 'listed examples only; not full PHP conformance, PHPT, Web, native ABI or side-effect coverage',
        'inputs_before': before, 'inputs_after': after, 'inputs_unchanged': before == after,
        'timeout_seconds': args.timeout, 'total': len(rows), 'passed': passed,
        'different': len(rows) - passed, 'results': rows,
    }
    (args.output / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f"{passed}/{len(rows)} exact process comparisons; inputs unchanged: {before == after}")
    return 0 if passed == len(rows) and before == after else 1


if __name__ == '__main__':
    raise SystemExit(main())
