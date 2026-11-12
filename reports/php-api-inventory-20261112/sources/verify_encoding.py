"""Exercise reference-value transport through actual pinned PHP, not ALL."""
from __future__ import annotations

import argparse
import base64
import json
import os
from pathlib import Path
import struct
import subprocess

from inventory import EXPECTED_PHP_SHA256, sha256, write_json


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--php', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    php = args.php.resolve(strict=True)
    output = args.output.resolve()
    if output.exists():
        parser.error('output already exists')
    if sha256(php) != EXPECTED_PHP_SHA256:
        parser.error('wrong oracle hash')
    output.mkdir(parents=True)
    worker = Path(__file__).with_name('reflect.php').resolve(strict=True)
    argv = [str(php), '-n', '-d', 'display_errors=stderr', '-d', 'error_reporting=-1',
            '-d', 'date.timezone=UTC', str(worker), '--encoding-self-test']
    process = subprocess.run(argv, cwd=output, capture_output=True, stdin=subprocess.DEVNULL,
                             timeout=30, creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
    (output / 'stdout.json').write_bytes(process.stdout)
    (output / 'stderr.bin').write_bytes(process.stderr)
    values = json.loads(process.stdout)['values']
    checks = {
        'oracle_exit_zero': process.returncode == 0,
        'stderr_empty': process.stderr == b'',
        'binary_string_exact': base64.b64decode(values['invalid_utf8']['bytes_base64']) == b'\x00\xff\x80A',
        'binary_string_length': values['invalid_utf8']['length_bytes'] == 4,
        'signed_zero_bits': values['negative_zero']['ieee754_big_endian_hex'] == struct.pack('>d', -0.0).hex(),
        'nan_classification': values['nan']['classification'] == 'nan',
        'positive_infinity_bits': values['positive_infinity']['ieee754_big_endian_hex'] == struct.pack('>d', float('inf')).hex(),
        'negative_infinity_bits': values['negative_infinity']['ieee754_big_endian_hex'] == struct.pack('>d', float('-inf')).hex(),
        'int64_no_json_precision_loss': values['int_max']['decimal'] == str(2**63 - 1),
        'enum_binary_backing_exact': base64.b64decode(values['enum']['backing_value']['bytes_base64']) == b'\x00\xff',
        'resource_explicitly_described': values['resource']['kind'] == 'resource' and values['resource']['status'] == 'DESCRIBED_NOT_SERIALIZED',
        'object_not_executed_or_dropped': values['object']['kind'] == 'object' and values['object']['status'] == 'DESCRIBED_NOT_SERIALIZED',
        'array_integer_and_string_keys_distinct': [entry['key']['kind'] for entry in values['array']['entries']] == ['int', 'string'],
        'unavailable_default_explicit': values['required_default']['status'] == 'NOT_AVAILABLE',
    }
    report = dict(status='PASS' if all(checks.values()) else 'FAIL', checks=checks,
                  passed=sum(checks.values()), total=len(checks), command=argv, exit_code=process.returncode,
                  php_sha256=sha256(php), worker_sha256=sha256(worker), candidate_execution=False)
    write_json(output / 'report.json', report)
    print(json.dumps(report, indent=2))
    return 0 if all(checks.values()) else 1


if __name__ == '__main__':
    raise SystemExit(main())
