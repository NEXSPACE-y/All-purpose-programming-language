"""Reuse frozen comparison logic/fixtures with explicitly pinned new core paths.

No execution on import. Root must authorize the serialized runtime loop first.
Expected channels come from separate stock-PHP reference processes, unchanged.
"""
from pathlib import Path
import hashlib
import importlib.util
import json
import sys

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
ORIGINAL=ROOT/'tools/candidates/php-byte-native/Compare-ByteNative.py'
BASE_REPORT=ROOT/'reports/php-byte-native-20261113/run02/report.json'
FIXTURES=ROOT/'reports/php-byte-native-20261113/run02/fixtures.json'


def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
 baseline=json.loads(BASE_REPORT.read_text(encoding='utf-8-sig'))
 assert digest(ORIGINAL)==baseline['inputs_before'][ORIGINAL.as_posix()]
 spec=importlib.util.spec_from_file_location('frozen_byte_comparator',ORIGINAL);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
 cases=json.loads(FIXTURES.read_text(encoding='utf-8-sig'))
 assert cases==module.fixtures(), 'Frozen fixture values must not change'
 cores={};builds={}
 for mode in ('legacy','callback'):
  record_path=ROOT/('reports/php-native-info-v2-20261113/build-'+mode+'01/build.json')
  record=json.loads(record_path.read_text(encoding='utf-8-sig'));path=Path(record['candidate']);assert digest(path)==record['candidate_sha256']
  assert record['inputs_before']==record['inputs_after'] and not record['runtime_executed']
  cores[mode]=path;builds[record_path]=digest(record_path);builds[path]=record['candidate_sha256']
  for label,source in record['input_paths'].items():builds[Path(source)]=record['inputs_before'][label]
 # Only explicit profile substitutions: new host/bridge source directory and
 # newly built own cores. Oracle/options/fixture/expected channels/timeout stay.
 module.HERE=HERE
 module.CORE=cores
 module.PINS.update(builds)
 module.PINS[Path(__file__).resolve()]=digest(Path(__file__).resolve())
 module.PINS[FIXTURES]=digest(FIXTURES)
 module.PINS[BASE_REPORT]=digest(BASE_REPORT)
 module.fixtures=lambda:cases
 original=module.main()
 # The frozen driver owns writing its raw terminal report. Add no output fixups.
 return original


if __name__=='__main__':raise SystemExit(main())
