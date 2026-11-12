"""Collect versioned reference API metadata from the pinned official PHP only.

No candidate execution, dependencies, services, network calls or ini-file edits.
Each DLL is observed in its own php -n process; failed loads remain failures.
"""
from __future__ import annotations

import argparse
import base64
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

EXPECTED_PHP_SHA256 = '0ac893499799256db6d3a54b0da73692e02311493922e6e4f86a062674a77d66'
SCHEMA_VERSION = '1.0'


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def json_bytes(value: object) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')) + '\n').encode('utf-8')


def write_json(path: Path, value: object) -> None:
    path.write_bytes(json_bytes(value))


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def raw_name(row: dict) -> bytes:
    return base64.b64decode(row['name_base64'], validate=True)


def metadata_hash(row: dict) -> str:
    return hashlib.sha256(json_bytes(row)).hexdigest()


def flatten(document: dict) -> dict[str, dict]:
    """One observed API exposure per key, preserving inherited member surfaces."""
    result = {}

    def add(kind: str, identity: bytes, symbol: str, row: dict, pointer: str, extension: object) -> None:
        key = kind + ':' + base64.b64encode(identity).decode('ascii')
        if key in result:
            raise ValueError(f'duplicate API exposure: {kind} {symbol}')
        result[key] = dict(kind=kind, symbol=symbol, metadata=row, pointer=pointer,
                           extension=extension, signature_sha256=metadata_hash(row))

    for index, row in enumerate(document['functions']):
        add('function', raw_name(row).lower(), row['name'], row, f'/functions/{index}', row['extension'])
    for index, row in enumerate(document['types']):
        lookup = row['lookup_name']
        type_identity = raw_name(lookup).lower()
        symbol = lookup['name']
        type_metadata = {key: value for key, value in row.items() if key not in ('methods', 'constants', 'properties')}
        add(row['kind'], type_identity, symbol, type_metadata, f'/types/{index}', row['extension'])
        for position, method in enumerate(row['methods']):
            add('method', type_identity + b'::' + raw_name(method).lower(), symbol + '::' + method['name'],
                method, f'/types/{index}/methods/{position}', method['extension'])
        for position, constant in enumerate(row['constants']):
            add('class_constant', type_identity + b'::' + raw_name(constant), symbol + '::' + constant['name'],
                constant, f'/types/{index}/constants/{position}', row['extension'])
        for position, prop in enumerate(row['properties']):
            add('property', type_identity + b'::$' + raw_name(prop), symbol + '::$' + prop['name'],
                prop, f'/types/{index}/properties/{position}', row['extension'])
    for index, row in enumerate(document['constants']):
        add('constant', raw_name(row), row['name'], row, f'/constants/{index}', row['extension'])
    for index, row in enumerate(document['ini']):
        add('ini', raw_name(row), row['name'], row, f'/ini/{index}', row['extensions'])
    return result


def counts(flat: dict[str, dict]) -> dict:
    return dict(sorted(Counter(row['kind'] for row in flat.values()).items()))


def run_reference(argv: list[str], directory: Path, timeout: float) -> tuple[dict, dict | None]:
    directory.mkdir(parents=True, exist_ok=False)
    start = time.monotonic()
    started = now()
    try:
        process = subprocess.run(argv, cwd=directory, stdin=subprocess.DEVNULL, capture_output=True,
                                 timeout=timeout, creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        stdout, stderr, code, state = process.stdout, process.stderr, process.returncode, 'EXITED'
    except subprocess.TimeoutExpired as error:
        stdout, stderr, code, state = error.stdout or b'', error.stderr or b'', None, 'TIMEOUT'
    except OSError as error:
        stdout, stderr, code, state = b'', str(error).encode('utf-8'), None, 'START_FAILED'
    # stdout.json is exact process output, not rewritten JSON; parse validity is recorded.
    (directory / 'stdout.json').write_bytes(stdout)
    (directory / 'stderr.bin').write_bytes(stderr)
    document = None
    parse_error = None
    try:
        document = json.loads(stdout.decode('utf-8'))
        if not isinstance(document, dict) or document.get('mode') != 'OFFICIAL_ORACLE_REFLECTION_ONLY':
            raise ValueError('worker mode/schema missing')
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as error:
        document = None
        parse_error = f'{type(error).__name__}: {error}'
    record = dict(command=argv, cwd=str(directory), started_utc=started, finished_utc=now(),
                  elapsed_seconds=time.monotonic() - start, state=state, exit_code=code,
                  stdout_path='stdout.json', stderr_path='stderr.bin', stdout_bytes=len(stdout), stderr_bytes=len(stderr),
                  stdout_sha256=sha256(directory / 'stdout.json'), stderr_sha256=sha256(directory / 'stderr.bin'),
                  stderr_utf8_preview=stderr[:32768].decode('utf-8', errors='backslashreplace'),
                  json_parse_error=parse_error)
    write_json(directory / 'process.json', record)
    return record, document


def delta(base: dict[str, dict], observed: dict[str, dict]) -> dict:
    added = sorted(set(observed) - set(base))
    removed = sorted(set(base) - set(observed))
    changed = sorted(key for key in set(base) & set(observed)
                     if base[key]['signature_sha256'] != observed[key]['signature_sha256'])

    def describe(keys: list[str], source: dict[str, dict]) -> list[dict]:
        return [dict(key=key, kind=source[key]['kind'], symbol=source[key]['symbol'],
                     signature_sha256=source[key]['signature_sha256'], pointer=source[key]['pointer']) for key in keys]
    return dict(added=describe(added, observed), removed=describe(removed, base), changed=describe(changed, observed),
                added_counts=dict(sorted(Counter(observed[key]['kind'] for key in added).items())),
                removed_counts=dict(sorted(Counter(base[key]['kind'] for key in removed).items())),
                changed_counts=dict(sorted(Counter(observed[key]['kind'] for key in changed).items())))


def parent_candidates(extension: object, kind: str, requirement_ids: set[str]) -> list[str]:
    extensions = extension if isinstance(extension, list) else [extension]
    candidates = []
    for name in extensions:
        if not isinstance(name, str):
            continue
        normalized = re.sub('[^A-Z0-9]', '', name.upper())
        for rid in requirement_ids:
            if not rid.startswith('EXT-'):
                continue
            suffix = re.sub('[^A-Z0-9]', '', rid[4:])
            if normalized == suffix or normalized == 'ZEND' + suffix:
                candidates.append(rid)
    if kind == 'ini' and 'LIB-INI' in requirement_ids:
        candidates.append('LIB-INI')
    if not candidates and 'LIB' in requirement_ids:
        candidates.append('LIB')
    return sorted(set(candidates))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--php', type=Path, required=True)
    parser.add_argument('--extension-dir', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--timeout', type=float, default=60, help='per reference-process guard; failed/timeout profiles are retained')
    args = parser.parse_args()
    args.php = args.php.resolve(strict=True)
    args.extension_dir = (args.extension_dir or args.php.parent / 'ext').resolve(strict=True)
    args.output = args.output.resolve()
    if args.output.exists():
        parser.error('output directory already exists; historical runs are never overwritten')
    if args.timeout <= 0:
        parser.error('timeout must be positive')
    if sha256(args.php) != EXPECTED_PHP_SHA256:
        parser.error('official oracle SHA-256 differs from fixed PHP 8.5.12 target')
    worker = Path(__file__).with_name('reflect.php').resolve(strict=True)
    driver = Path(__file__).resolve()
    dlls = sorted(args.extension_dir.glob('*.dll'), key=lambda path: path.name.lower())
    if len(dlls) != 36:
        parser.error(f'expected the approved 36 local official DLLs, found {len(dlls)}')
    watched = [args.php, worker, driver, *dlls]
    inputs_before = {str(path): sha256(path) for path in watched}
    args.output.mkdir(parents=True)
    write_json(args.output / 'inputs-before.json', inputs_before)
    repo = driver.parents[3]
    matrix_path = repo / 'docs' / 'PHP_REQUIREMENTS_MATRIX.json'
    matrix = json.loads(matrix_path.read_text(encoding='utf-8-sig')) if matrix_path.exists() else {}
    requirement_ids = {row['id'] for row in matrix.get('requirements', [])}
    matrix_hash = sha256(matrix_path) if matrix_path.exists() else None
    profiles = []
    union = {}
    base_flat = {}
    base_extensions = set()
    base_target = None
    arguments = [str(args.php), '-n', '-d', 'display_errors=stderr', '-d', 'error_reporting=-1', '-d', 'date.timezone=UTC']
    started = now()
    for index, dll in enumerate([None, *dlls]):
        profile_id = 'base' if dll is None else dll.stem
        directory = args.output / 'profiles' / profile_id
        argv = arguments + ([] if dll is None else ['-d', 'extension=' + str(dll)]) + [str(worker)]
        process, document = run_reference(argv, directory, args.timeout)
        record = dict(profile_id=profile_id, requested_dll=str(dll) if dll else None,
                      requested_dll_sha256=inputs_before[str(dll)] if dll else None,
                      process=process, inventory_path=str((directory / 'stdout.json').relative_to(args.output)))
        observed = {}
        if document is not None:
            record['target'] = document['target']
            record['collection_errors'] = document['collection_errors']
            record['worker_warning_count'] = len(document['warnings_during_worker'])
            observed = flatten(document)
            record['counts'] = counts(observed)
            record['observed_api_exposures'] = len(observed)
            loaded = {extension['name'] for extension in document['extensions']}
            if dll is None:
                base_flat = observed
                base_extensions = loaded
                base_target = document['target']
            added_extensions = sorted(loaded - base_extensions)
            record['loaded_extensions'] = sorted(loaded)
            record['new_loaded_extensions_vs_base'] = added_extensions
            record['load_status'] = ('BASE_OBSERVED' if dll is None else ('LOADED' if added_extensions else 'NOT_LOADED'))
            record['reflection_status'] = 'COMPLETE_FOR_OBSERVED_PROCESS' if not document['collection_errors'] else 'PARTIAL_WITH_COLLECTION_ERRORS'
            profile_delta = delta(base_flat, observed)
            write_json(directory / 'delta-vs-base.json', profile_delta)
            record['delta_counts'] = {kind: profile_delta[kind + '_counts'] for kind in ('added', 'removed', 'changed')}
            for key, item in observed.items():
                leaf = union.setdefault(key, dict(api_kind=item['kind'], symbol=item['symbol'], extension=item['extension'], variants={}))
                variant = leaf['variants'].setdefault(item['signature_sha256'], dict(profiles=[], observations=[]))
                variant['profiles'].append(profile_id)
                variant['observations'].append(dict(profile=profile_id, inventory=record['inventory_path'], pointer=item['pointer']))
        else:
            record.update(load_status='UNMEASURED_PROCESS_FAILED', reflection_status='UNAVAILABLE', counts={})
        if process['state'] != 'EXITED' or process['exit_code'] != 0:
            record['load_status'] = 'UNMEASURED_PROCESS_FAILED'
        profiles.append(record)
        write_json(directory / 'profile-summary.json', record)
        print(f'{index + 1}/37 {profile_id}: {record["load_status"]}; exit={process["exit_code"]}; '
              f'API={record.get("observed_api_exposures", 0)}; stderr={process["stderr_bytes"]}', flush=True)
    leaves = []
    for key, item in sorted(union.items()):
        identity_hash = hashlib.sha256(key.encode('ascii')).hexdigest()
        leaf = dict(id='PHP8512.API.' + item['api_kind'].upper() + '.' + identity_hash,
                    kind='leaf_candidate', stage=1, state='UNVERIFIED', candidate_implementation='NOT_ASSESSED',
                    api_key=key, api_kind=item['api_kind'], symbol=item['symbol'], extension=item['extension'],
                    parent_candidates=parent_candidates(item['extension'], item['api_kind'], requirement_ids),
                    signature_variants=[dict(signature_sha256=signature, **variant) for signature, variant in sorted(item['variants'].items())],
                    tests=[], note='Reference API existence/signature only; semantic requirements and candidate tests must be expanded separately')
        leaves.append(leaf)
    with (args.output / 'api-leaves.jsonl').open('wb') as stream:
        for leaf in leaves:
            stream.write(json_bytes(leaf))
    inputs_after = {str(path): sha256(path) for path in watched}
    write_json(args.output / 'inputs-after.json', inputs_after)
    failures = [row['profile_id'] for row in profiles if row['load_status'] not in ('LOADED', 'BASE_OBSERVED')]
    errors = [row['profile_id'] for row in profiles if row['reflection_status'] != 'COMPLETE_FOR_OBSERVED_PROCESS']
    summary = dict(schema_version=SCHEMA_VERSION, status='NOT_COMPLETE', measurement='OFFICIAL_ORACLE_API_INVENTORY_ONLY',
                   candidate_execution=False, exhaustive=False, php_full_compatibility=False,
                   started_utc=started, finished_utc=now(), fixed_oracle_sha256=EXPECTED_PHP_SHA256,
                   target=base_target, profile_arguments=arguments, timeout_seconds=args.timeout,
                   expected_extension_dlls=36, extension_profiles_observed=36, profiles=len(profiles),
                   loaded_extension_profiles=sum(row['load_status'] == 'LOADED' for row in profiles),
                   failed_or_unmeasured_profiles=failures, profiles_with_collection_errors=errors,
                   base_counts=counts(base_flat), union_counts=dict(sorted(Counter(row['api_kind'] for row in leaves).items())),
                   union_api_exposures=len(leaves), inputs_unchanged=inputs_before == inputs_after,
                   unmeasured=['Linux x64', 'non-CLI SAPIs and hosting', 'combined-extension profiles',
                               'failed DLL public APIs', 'arbitrary third-party native extensions',
                               'compiled factory INI defaults', 'candidate semantics/behavior/ABI compatibility'],
                   profile_results=profiles)
    write_json(args.output / 'summary.json', summary)
    write_json(args.output / 'requirements-linkage.json', dict(schema_version='1.0', status='PROPOSED_LEAF_INPUT_ONLY',
               requirements_matrix=str(matrix_path), requirements_matrix_sha256_at_start=matrix_hash,
               leaf_file='api-leaves.jsonl', leaf_file_sha256=sha256(args.output / 'api-leaves.jsonl'),
               rows=len(leaves), rules=['No existing requirements or VERIFIED states changed',
               'parent_candidates are mechanical extension-name matches requiring review',
               'API existence is not behavior coverage; overload/errors/state/SAPI/ABI tests remain to be specified'],
               observed_parent_counts=dict(sorted(Counter(parent for leaf in leaves for parent in leaf['parent_candidates']).items()))))
    reproducible = [sys.executable, '-B', str(driver), '--php', str(args.php), '--extension-dir', str(args.extension_dir),
                    '--output', '<NEW_OUTPUT_DIRECTORY>', '--timeout', str(args.timeout)]
    write_json(args.output / 'reproduce.json', dict(argv=reproducible, notes='Choose a new output directory; no historical run is replaced'))
    print(f'Union API exposures: {len(leaves)}; loaded DLL profiles: {summary["loaded_extension_profiles"]}/36; '
          f'failed/unmeasured: {failures}; inputs unchanged: {summary["inputs_unchanged"]}', flush=True)
    # Missing dependencies are expected observations; still fail closed for inventory completeness.
    return 0 if not failures and not errors and summary['inputs_unchanged'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
