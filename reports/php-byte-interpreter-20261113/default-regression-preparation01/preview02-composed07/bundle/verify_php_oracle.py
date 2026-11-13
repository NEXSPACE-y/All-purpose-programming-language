#!/usr/bin/env python3
"""Re-evaluate saved PHP CLI oracle cases; never executes the ALL adapter."""
import json
from pathlib import Path
import subprocess
import tempfile
import sys
root = Path(__file__).resolve().parent
cases = json.loads((root/'PHP_v3_10_typed_oracle_cases.json').read_text(encoding='utf-8'))
with tempfile.TemporaryDirectory() as tmp:
    source = Path(tmp)/'case.php'
    for i, case in enumerate(cases, 1):
        source.write_text(case['code'], encoding='utf-8')
        result = subprocess.run(['php','-d','display_errors=0',str(source)], capture_output=True)
        actual = result.stdout.decode('utf-8', errors='replace')
        if 'expected' in case:
            good = result.returncode == 0 and actual == case['expected']
        else:
            error_text = result.stderr.decode('utf-8', errors='replace')
            expected_php_error = ('A void function must not return a value'
                                  if case['name'] == 'reject void return value'
                                  else 'Uncaught TypeError')
            good = result.returncode != 0 and expected_php_error in error_text
        if not good:
            print(f"FAIL PHP oracle #{i}: {case['name']}", file=sys.stderr)
            sys.exit(1)
print(f'PASS PHP native reference: {len(cases)}/{len(cases)} (ALL adapter not executed)')
