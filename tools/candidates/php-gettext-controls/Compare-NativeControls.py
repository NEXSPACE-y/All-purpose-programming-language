"""Use Compare05 unchanged with a new frozen PREP and explicit env setup."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import os
import sys

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
REPORT=ROOT/'reports/php-native-gettext-20261113'
ORIGINAL=ROOT/'tools/candidates/php-native-gettext/Compare-Gettext05.py'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
KEYS=['LC_ALL','LC_MESSAGES','LANG','LANGUAGE','LC_CTYPE']

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--profile',choices=['value','catalog'],required=True);parser.add_argument('--execute',action='store_true');parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    if not args.execute:raise SystemExit('Await root serialized runtime signal before --execute')
    prep=REPORT/(args.profile+'-controls8-prepared01');provenance=json.loads((prep/'provenance.json').read_text())
    assert sha(ORIGINAL)==provenance['comparator_sha256']
    pins=json.loads((HERE/'prepared-profile-pins.json').read_text())
    assert sha(prep/'prepared-manifest.json')==pins[args.profile]
    spec=importlib.util.spec_from_file_location('frozen_compare05',ORIGINAL);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    module.PREP=prep;module.PINS[prep/'prepared-manifest.json']=pins[args.profile]
    for p in [Path(__file__).resolve(),HERE/'prepared-profile-pins.json',Path(provenance['reference_generator']),Path(provenance['preparer'])]:module.PINS[p]=sha(p)
    assert sha(Path(provenance['reference_generator']))==provenance['reference_generator_sha256']
    assert sha(Path(provenance['preparer']))==provenance['preparer_sha256']
    if args.profile=='catalog':
        for name in ['copied_mo','independent_locale_manifest']:
            path=Path(provenance[name]);assert sha(path)==provenance[name+'_sha256'];module.PINS[path]=provenance[name+'_sha256']
    before={key:os.environ.get(key)for key in KEYS};argv=sys.argv[:];result=None
    try:
        if args.profile=='catalog':
            for key in KEYS:os.environ.pop(key,None)
        sys.argv=[str(ORIGINAL),'--execute','--output',str(args.output.resolve())]
        result=module.main()
    finally:
        for key,value in before.items():
            if value is None:os.environ.pop(key,None)
            else:os.environ[key]=value
        sys.argv=argv
        if args.output.exists():
            (args.output/'wrapper-context.json').write_text(json.dumps({'status':'EXPLICIT_PROFILE_ORCHESTRATION_NO_OUTPUT_NORMALIZATION','wrapper_argv':argv,'profile':args.profile,'original_comparator':str(ORIGINAL),'original_comparator_sha256':sha(ORIGINAL),'wrapper_sha256':sha(Path(__file__).resolve()),'locale_environment_before':before,'locale_environment_after':{key:os.environ.get(key)for key in KEYS},'locale_keys_removed_only_inside_this_wrapper':KEYS if args.profile=='catalog'else[],'original_comparison_function_changed':False,'timeout_seconds':30,'original_comparator_returned_status':result},indent=2)+'\n',encoding='utf-8')
    return result

if __name__=='__main__':raise SystemExit(main())
