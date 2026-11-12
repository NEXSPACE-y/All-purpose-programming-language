"""Audit stored reference inventory transport and source links without rerunning PHP."""
from __future__ import annotations

import argparse
import base64
from collections import Counter
import json
import math
from pathlib import Path
import struct

from inventory import EXPECTED_PHP_SHA256, flatten, metadata_hash, sha256, write_json


def inspect_values(value: object, counts: Counter) -> None:
    if isinstance(value, dict):
        kind = value.get('kind')
        if kind == 'string':
            raw = base64.b64decode(value['bytes_base64'], validate=True)
            assert len(raw) == value['length_bytes'], 'PHP byte-string length mismatch'
            counts['byte_strings'] += 1
        elif kind == 'int':
            assert str(int(value['decimal'])) == value['decimal'], 'integer decimal transport mismatch'
            counts['integers'] += 1
        elif kind == 'float':
            number = struct.unpack('>d', bytes.fromhex(value['ieee754_big_endian_hex']))[0]
            classification = 'nan' if math.isnan(number) else ('+infinity' if number > 0 else '-infinity') if math.isinf(number) else 'finite'
            assert classification == value['classification'], 'float class/bit mismatch'
            counts['float_' + classification] += 1
        if 'name_base64' in value:
            raw = base64.b64decode(value['name_base64'], validate=True)
            try:
                assert raw.decode('utf-8') == value['name']
            except UnicodeDecodeError:
                assert value['name'] == '<non-UTF8 identifier>'
            counts['identifiers'] += 1
        for child in value.values():
            inspect_values(child, counts)
    elif isinstance(value, list):
        for child in value:
            inspect_values(child, counts)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    run = args.run.resolve(strict=True)
    if args.output.exists():
        parser.error('output exists')
    summary = json.loads((run / 'summary.json').read_text(encoding='utf-8'))
    before = json.loads((run / 'inputs-before.json').read_text(encoding='utf-8'))
    after = json.loads((run / 'inputs-after.json').read_text(encoding='utf-8'))
    errors = []
    checks = []
    value_counts = Counter()
    flat_profiles = {}
    general_info = {}
    try:
        assert before == after and summary['inputs_unchanged']
        for path, expected in after.items():
            assert sha256(Path(path)) == expected, f'input changed after run: {path}'
        checks.append('All pinned oracle/DLL/worker/driver hashes equal before, after and audit-time bytes')
        assert summary['fixed_oracle_sha256'] == EXPECTED_PHP_SHA256
        assert len(summary['profile_results']) == 37
        for profile in summary['profile_results']:
            inventory_path = run / profile['inventory_path']
            process = profile['process']
            assert sha256(inventory_path) == process['stdout_sha256']
            assert sha256(inventory_path.parent / 'stderr.bin') == process['stderr_sha256']
            command = process['command']
            extension_args = [item for item in command if item.startswith('extension=')]
            assert extension_args == ([] if profile['requested_dll'] is None else ['extension=' + profile['requested_dll']])
            assert command[1:8] == ['-n', '-d', 'display_errors=stderr', '-d', 'error_reporting=-1', '-d', 'date.timezone=UTC']
            document = json.loads(inventory_path.read_text(encoding='utf-8'))
            target = document['target']
            assert target['php_version'] == '8.5.12' and target['sapi'] == 'cli' and target['os_family'] == 'Windows'
            assert target['zts'] == 1 and target['int_size'] == 8
            assert document['candidate_execution'] is False and not document['collection_errors']
            assert all(row['internal'] for row in document['functions'])
            assert all(row['internal'] for row in document['types'])
            assert not any(row['name'].startswith('all_api_') for row in document['functions'])
            assert not any(row['name'] == 'ALL_API_EncodingProbe' for row in document['types'])
            for function in document['functions'] + [method for row in document['types'] for method in row['methods']]:
                params = function['parameters']
                assert len(params) == function['parameter_count']
                assert [row['position'] for row in params] == list(range(len(params)))
                assert function['required_parameter_count'] <= len(params)
                assert all('status' in row['default'] for row in params)
            inspect_values(document, value_counts)
            observed = flatten(document)
            assert dict(Counter(row['kind'] for row in observed.values())) == profile['counts']
            flat_profiles[profile['profile_id']] = observed
            if profile['profile_id'] == 'base':
                general = base64.b64decode(target['phpinfo_general']['bytes_base64']).decode('utf-8')
                general_info = dict(line.split(' => ', 1) for line in general.splitlines() if ' => ' in line)
        checks.append('All37 profiles retain exact channels and prescribed flags; PHP8.5.12 ZTS x64 Windows CLI; no worker entities in target API')
        checks.append('Every callable retains parameter order/count/default-state; encoded bytes/int64/float bits validated throughout stored metadata')
        seen = set()
        union_counts = Counter()
        leaf_count = 0
        for line in (run / 'api-leaves.jsonl').read_text(encoding='utf-8').splitlines():
            leaf = json.loads(line)
            assert leaf['id'] not in seen
            seen.add(leaf['id'])
            assert leaf['kind'] == 'leaf_candidate' and leaf['state'] == 'UNVERIFIED'
            assert leaf['candidate_implementation'] == 'NOT_ASSESSED' and leaf['tests'] == []
            union_counts[leaf['api_kind']] += 1
            leaf_count += 1
            for variant in leaf['signature_variants']:
                for observation in variant['observations']:
                    actual = flat_profiles[observation['profile']][leaf['api_key']]
                    assert actual['pointer'] == observation['pointer']
                    assert actual['signature_sha256'] == variant['signature_sha256']
                    assert metadata_hash(actual['metadata']) == variant['signature_sha256']
        assert leaf_count == summary['union_api_exposures'] and dict(union_counts) == summary['union_counts']
        checks.append('Every union leaf has unique ID, UNVERIFIED state, exact profile/pointer/signature references; counts agree')
    except (AssertionError, KeyError, ValueError, OSError) as error:
        errors.append(f'{type(error).__name__}: {error}')
    report = dict(status='PASS' if not errors else 'FAIL', meaning='Stored reference data integrity only; not inventory exhaustiveness or PHP compatibility',
                  checks=checks, errors=errors, value_transport_counts=dict(value_counts),
                  phpinfo_general_fields=general_info, candidate_execution=False,
                  run_summary_sha256=sha256(run / 'summary.json'), leaf_file_sha256=sha256(run / 'api-leaves.jsonl'))
    write_json(args.output, report)
    print(json.dumps(report, indent=2))
    return 0 if not errors else 1


if __name__ == '__main__':
    raise SystemExit(main())
