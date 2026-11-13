"""Merge reviewed disjoint edits from the exact frozen native source.

Fail closed on changed inputs, overlapping edits or an existing output directory.
This only creates a candidate; it never updates package or installs the runtime.
"""
from pathlib import Path
import argparse
import difflib
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'tools/candidates/php-native/ALL_PHP_native_candidate.ps1'
EXPECTED_BASE = '47c8edb9e39bffe3ed5475f2aeed7e36673a798d2f72baf0cb60abc39695322d'

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--part', nargs=2, action='append', metavar=('PATH', 'SHA256'), required=True)
    parser.add_argument('--base',type=Path,default=BASE)
    parser.add_argument('--expected-base-sha256',default=EXPECTED_BASE)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    out = args.output.resolve()
    if out.exists():
        parser.error('Output exists; preserve it and select a fresh path.')
    base=args.base.resolve(strict=True)
    expected_base=args.expected_base_sha256
    raw = base.read_bytes()
    if sha(raw) != expected_base:
        parser.error('Frozen base hash changed.')
    original = raw.splitlines(keepends=True)
    edits = []
    inputs = []
    for filename, expected in args.part:
        path = Path(filename).resolve(strict=True)
        data = path.read_bytes()
        if sha(data) != expected:
            parser.error('Part hash differs: ' + str(path))
        lines = data.splitlines(keepends=True)
        opcodes = difflib.SequenceMatcher(a=original, b=lines, autojunk=False).get_opcodes()
        part_edits = []
        for kind, i1, i2, j1, j2 in opcodes:
            if kind == 'equal':
                continue
            if max(i2-i1, j2-j1) > 500:
                parser.error('Unexpectedly broad edit; review newline/encoding and scope: ' + str(path))
            edits.append((i1, i2, lines[j1:j2], str(path)))
            part_edits.append({'kind':kind, 'base_start':i1, 'base_end':i2, 'part_start':j1, 'part_end':j2})
        if not part_edits:
            parser.error('Part has no edits: ' + str(path))
        inputs.append({'path':str(path), 'sha256':expected, 'edits':part_edits})
    edits.sort(key=lambda e: (e[0], e[1]))
    result = []
    end = 0
    previous = None
    for start, stop, replacement, owner in edits:
        if start < end or (previous is not None and start == previous[0]):
            parser.error('Edits overlap; manual review required: ' + owner)
        result.extend(original[end:start])
        result.extend(replacement)
        end = stop
        previous = (start, stop)
    result.extend(original[end:])
    generated = b''.join(result)
    # Detect any input changing while its diff was computed.
    if sha(base.read_bytes()) != expected_base or any(sha(Path(i['path']).read_bytes()) != i['sha256'] for i in inputs):
        parser.error('An input changed during integration.')
    out.mkdir(parents=True)
    candidate = out / 'ALL_PHP_integrated_candidate.ps1'
    candidate.write_bytes(generated)
    (out / 'base.snapshot.ps1').write_bytes(raw)
    (out / 'integration.patch').write_text(''.join(difflib.unified_diff(raw.decode('utf-8-sig').splitlines(True), generated.decode('utf-8-sig').splitlines(True), fromfile='frozen-native-base', tofile='integrated-candidate')), encoding='utf-8', newline='')
    report = {'status':'ISOLATED_NOT_VERIFIED', 'base':str(base), 'base_sha256':expected_base, 'parts':inputs, 'candidate':str(candidate), 'candidate_sha256':sha(generated), 'package_modified':False, 'merge':'Nonoverlapping line edits with input hash guards; no semantic compatibility inference'}
    (out / 'provenance.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({'candidate':str(candidate), 'sha256':sha(generated), 'parts':len(inputs), 'edits':len(edits)}))

if __name__ == '__main__':
    main()
