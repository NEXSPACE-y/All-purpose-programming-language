"""Read-only package/fixture integrity helpers for isolated default regression."""
from pathlib import Path
import hashlib
import json
import re
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
POWERSHELL = Path('C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe')
REGISTRY = HERE / 'original-inputs.json'
BYTE_RUNTIME_SHA256 = '18d50efb55d8a333424149e4ab37428e102b1ac938240e50358ee3c8ab89466b'

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def read_json(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))

def save(path, value):
    Path(path).write_text(json.dumps(value, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')

def snapshot(root):
    root = Path(root).resolve(strict=True)
    result = {}
    for path in sorted(root.rglob('*')):
        if path.is_symlink():
            raise ValueError('A package symlink is not a regular byte-copy input: '+str(path))
        if path.is_file():
            if not path.resolve().is_relative_to(root):
                raise ValueError('Package input escapes its resolved root')
            result[path.relative_to(root).as_posix()] = {'bytes': path.stat().st_size, 'sha256': sha(path)}
    return result

def manifest(root):
    root = Path(root).resolve(strict=True)
    rows = {}
    for line in (root/'SHA256SUMS.txt').read_text(encoding='utf-8-sig').splitlines():
        if not line.strip():
            continue
        match = re.fullmatch(r'([0-9a-fA-F]{64})  (.+)', line)
        if not match:
            raise ValueError('Malformed package SHA256SUMS entry')
        raw = match[2].replace('\\', '/')
        relative = Path(raw)
        if relative.is_absolute() or '..' in relative.parts or ':' in raw:
            raise ValueError('Unsafe manifest path: '+raw)
        if raw.casefold() in {x.casefold() for x in rows}:
            raise ValueError('Duplicate manifest path: '+raw)
        path = root/relative
        if not path.is_file() or not path.resolve().is_relative_to(root):
            raise ValueError('Missing/escaping manifest input: '+raw)
        actual = sha(path)
        if actual != match[1].lower():
            raise ValueError('Manifest hash mismatch: '+raw)
        rows[raw] = actual
    files = set(snapshot(root)) - {'SHA256SUMS.txt'}
    if files != set(rows):
        raise ValueError('Manifest coverage differs from actual regular package files')
    return rows

def fixture_array(path):
    value = read_json(path)
    if isinstance(value, list) and len(value)==1 and isinstance(value[0], list):
        value=value[0]
    if not isinstance(value, list):
        raise ValueError('Fixture collection is not an array: '+str(path))
    return value

def fixture_inventory(root):
    root = Path(root)
    script = (root/'ALL_PHP_v3_16_test.ps1').read_text(encoding='utf-8-sig')
    entries = re.findall(r"@\{File='([^']+)'; Count=(\d+); Category='([^']+)'(?:; Diagnostics=\$true)?\}", script)
    if len(entries)!=32:
        raise ValueError('Original32 fixture collection declarations changed')
    expected_lines = []
    collections = []
    for file, declared, category in entries:
        rows = fixture_array(root/file)
        if len(rows)!=int(declared):
            raise ValueError('Original collection count changed: '+file)
        collections.append({'path': file, 'count': len(rows), 'sha256': sha(root/file)})
        expected_lines.extend('['+category+']: '+str(row['name']) for row in rows)
    pairs = [x for x in fixture_array(root/'ALL_math_cases.json') if x.get('mode')=='pair']
    if len(pairs)!=17 or len(expected_lines)+len(pairs)!=940:
        raise ValueError('Original940 definition/parity counts changed')
    expected_lines.extend('[historical parity]: '+str(row['name']) for row in pairs)
    extra_file = 'PHP_v3_17_namespace_runtime_oracle_cases.json'
    extra = fixture_array(root/extra_file)
    if len(extra)!=25:
        raise ValueError('Additional namespace25 definition count changed')
    expected_lines.extend('[runtime namespaces]: '+str(row['name']) for row in extra)
    return {'collections': collections, 'historicalPairCount': len(pairs),
            'additional': {'path': extra_file, 'count': len(extra), 'sha256': sha(root/extra_file)},
            'expectedCaseLines': expected_lines, 'total': len(expected_lines)}

def original_git_check(evidence_root, label):
    registry = read_json(REGISTRY)
    paths = registry['trackedPaths']
    if len(paths)!=34:
        raise ValueError('Expected unchanged original34 tracked inputs')
    command=['git','diff','--exit-code',registry['original940Base'],'--',*paths]
    process=subprocess.run(command,cwd=ROOT,capture_output=True)
    (Path(evidence_root)/(label+'.stdout.bin')).write_bytes(process.stdout)
    (Path(evidence_root)/(label+'.stderr.bin')).write_bytes(process.stderr)
    return {'command':command,'exit_code':process.returncode,'base':registry['original940Base'],
            'trackedPaths':paths,'stdout_sha256':hashlib.sha256(process.stdout).hexdigest(),
            'stderr_sha256':hashlib.sha256(process.stderr).hexdigest(),
            'measurement':'Git tracked-content comparison, plus separate actual byte hash snapshots; no expectation rewrite'}

def byte_runtime_pin(candidate):
    source=Path(candidate).read_text(encoding='utf-8-sig')
    paths=re.findall(r"^        \$phpByteRuntimePath = '([^']+)'",source,re.M)
    hashes=re.findall(r"^        \$phpByteRuntimeHash = '([0-9a-f]{64})'",source,re.M)
    if len(paths)!=1 or len(hashes)!=1:
        raise ValueError('Expected one existing absolute byte-runtime bootstrap; do not rewrite it')
    path=Path(paths[0])
    if not path.is_absolute() or hashes[0]!=BYTE_RUNTIME_SHA256 or sha(path)!=hashes[0]:
        raise ValueError('Canonical byte runtime absolute path/hash differs from approved runtime01')
    return {'path':str(path),'sha256':hashes[0],'rewritten':False}

def protected_main():
    path=Path.home()/'ALL/ALL.ps1'
    return {'path':str(path),'exists':path.is_file(),'sha256':sha(path) if path.is_file() else None,
            'executed':False}
