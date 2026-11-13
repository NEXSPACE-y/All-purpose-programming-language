"""Build a new immutable candidate from pinned v3.20 and approved byte modules."""
from pathlib import Path
import argparse
import difflib
import hashlib
import importlib.util
import json
from CoreByteEdits import apply as core_apply

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--base', type=Path, default=ROOT/'package/ALL_PHP_v3_12_adapter.ps1')
parser.add_argument('--expected-base-sha256', default='5856687f7abd1471b4af7af9827ca2d17a011e836ad2852bf1d7993298fddc9f')
parser.add_argument('--runtime', type=Path, required=True)
parser.add_argument('--expected-runtime-sha256', required=True)
parser.add_argument('--typed-keys', action='store_true')
parser.add_argument('--string-builtins', action='store_true')
parser.add_argument('--native-bytes', action='store_true')
parser.add_argument('--string-offsets', action='store_true')
parser.add_argument('--json-bytes', action='store_true')
parser.add_argument('--symbols', action='store_true')
parser.add_argument('--value-boundaries', action='store_true')
parser.add_argument('--callback-arguments', action='store_true')
parser.add_argument('--hex-builtin', action='store_true')
parser.add_argument('--array-diagnostics', action='store_true')
parser.add_argument('--diagnostic-callsite', action='store_true')
parser.add_argument('--trigger-coercion', action='store_true')
parser.add_argument('--enum-coercion', action='store_true')
parser.add_argument('--references', action='store_true')
parser.add_argument('--array-index', action='store_true')
parser.add_argument('--array-quiet', action='store_true')
parser.add_argument('--output-directory', type=Path, required=True)
args = parser.parse_args()
destination = args.output_directory.resolve()
if destination.exists():
    raise SystemExit('Destination exists: preserve measured revisions')

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

base = args.base.resolve(strict=True)
runtime = args.runtime.resolve(strict=True)
if digest(base) != args.expected_base_sha256:
    raise SystemExit('Base source hash differs from pinned revision')
if digest(runtime) != args.expected_runtime_sha256:
    raise SystemExit('Byte runtime hash differs from pinned revision')
before = base.read_bytes().decode('utf-8-sig')
after = core_apply(before, runtime, args.expected_runtime_sha256)
modules = ['CoreByteEdits.py', 'ByteValueHelpers.ps1.fragment']
for enabled, name in [(args.typed_keys,'TypedKeyEdits.py'),(args.string_builtins,'StringBuiltinEdits.py'),
                      (args.native_bytes,'NativeByteEdits.py'),(args.string_offsets,'StringOffsetEdits.py'),
                      (args.json_bytes,'JsonByteEdits.py'),(args.symbols,'SymbolEdits.py'),
                      (args.value_boundaries,'ValueBoundaryEdits.py'),(args.callback_arguments,'CallbackArgumentEdits.py'),
                      (args.hex_builtin,'HexBuiltinEdits.py'),(args.array_diagnostics,'ArrayDiagnosticEdits.py'),
                      (args.diagnostic_callsite,'DiagnosticCallsiteEdits.py'),(args.trigger_coercion,'TriggerCoercionEdits.py'),
                      (args.enum_coercion,'EnumCoercionEdits.py'),(args.references,'ReferenceDisplayEdits.py'),
                      (args.array_index,'ArrayIndexEdits.py'),(args.array_quiet,'ArrayQuietReadEdits.py')]:
    if not enabled:
        continue
    path = HERE/name
    spec = importlib.util.spec_from_file_location(path.stem,path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    after = module.apply(after)
    modules.append(name)
destination.mkdir(parents=True)
candidate = destination/'ALL_PHP_byte_candidate.ps1'
candidate.write_bytes(b'\xef\xbb\xbf'+after.encode('utf-8'))
(destination/'base.snapshot.ps1').write_bytes(base.read_bytes())
snapshot_directory=destination/'module-snapshots'
snapshot_directory.mkdir()
for name in modules:
    (snapshot_directory/name).write_bytes((HERE/name).read_bytes())
(snapshot_directory/'Build-ByteInterpreter.py').write_bytes(Path(__file__).resolve().read_bytes())
(destination/'source.patch').write_text(''.join(difflib.unified_diff(before.splitlines(True),after.splitlines(True),fromfile='v3.20-'+args.expected_base_sha256,tofile='byte-migration-candidate')),encoding='utf-8',newline='')
record = {
    'status':'BUILT_NOT_RUNTIME_VERIFIED',
    'full_php_compatibility':False,
    'approval':'docs/decisions/PHP_BYTE_MODEL_APPROVAL_20261113.md',
    'base':str(base),'base_sha256':args.expected_base_sha256,
    'runtime':str(runtime),'runtime_sha256':args.expected_runtime_sha256,
    'candidate':str(candidate),'candidate_sha256':digest(candidate),
    'modules':{name:digest(HERE/name) for name in modules},
    'module_snapshots':{str((snapshot_directory/name).relative_to(destination)):digest(snapshot_directory/name) for name in modules},
    'base_snapshot_sha256':digest(destination/'base.snapshot.ps1'),
    'builder_sha256':digest(Path(__file__).resolve()),
    'typed_keys':args.typed_keys,'string_builtins':args.string_builtins,
    'native_bytes':args.native_bytes,'symbols':args.symbols,
    'string_offsets':args.string_offsets,
    'json_bytes':args.json_bytes,
    'value_boundaries':args.value_boundaries,'references':args.references,
    'callback_arguments':args.callback_arguments,'hex_builtin':args.hex_builtin,
    'array_diagnostics':args.array_diagnostics,
    'diagnostic_callsite':args.diagnostic_callsite,
    'trigger_coercion':args.trigger_coercion,'enum_coercion':args.enum_coercion,
    'array_index':args.array_index,
    'array_quiet':args.array_quiet,
    'stock_php_execution_delegation':False,'package_modified':False,
    'limitations':[
        'Source decoding and host symbol boundaries still require valid UTF-8.',
        'Diagnostics and exception traces are not yet byte-native.',
        'Legacy builtins not listed by module remain explicit UTF-8 boundaries.',
        'Numeric classification still materializes an ASCII view at an Int32 interop boundary.',
        'The isolated adapter embeds an absolute pinned assembly path; portable packaging pending.',
        'Linux and all SAPI/native-extension coverage remain incomplete.'
    ]
}
(destination/'provenance.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'candidate':str(candidate),'sha256':record['candidate_sha256']}))
