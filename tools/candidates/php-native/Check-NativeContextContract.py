#!/usr/bin/env python3
"""Validate explicit NativeContext opt-in and the worker's AST rejection guard."""
from pathlib import Path
import argparse
import importlib.util
import json
import sys

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
sys.dont_write_bytecode=True
spec=importlib.util.spec_from_file_location('all_strict_contract',ROOT/'tools/differential/evaluate.py')
strict=importlib.util.module_from_spec(spec);spec.loader.exec_module(strict)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();out=args.output.resolve()
    if out.exists():parser.error('Preserve existing evidence: choose a fresh output directory')
    out.mkdir(parents=True)
    ps=Path('C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe')
    php=Path.home()/'ALL_php_oracle/php-8.5.12-ts-x64/php.exe'
    extension=php.parent/'ext/php_dl_test.dll'
    core=ROOT/'native/php85abi/out/windows-x64-ts/php8ts.dll'
    candidate=HERE/'ALL_PHP_native_candidate.ps1'
    frozen=ROOT/'tools/candidates/php-v3_18/ALL_PHP_v3_18_candidate.ps1'
    worker=ROOT/'tools/abi/Invoke-NativePhpWorker.ps1'
    before={str(p):strict.sha256(p) for p in [ps,php,extension,core,candidate,frozen,worker]}
    source=out/'must-not-execute.php';source.write_bytes(b"<?php echo 'SOURCE_EXECUTED';")
    meta=out/'absent-param.native.json'
    rejected=strict.run_process([str(ps),'-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(worker),'-AdapterPath',str(frozen),'-SourcePath',str(source),'-CorePath',str(core),'-ExtensionPath',str(extension),'-MetadataPath',str(meta),'-ExpectedCoreHash',strict.sha256(core)],out,30)
    info=json.loads(meta.read_text(encoding='utf-8-sig')) if meta.exists() else {}
    guard=rejected['exit_code']==1 and rejected['stdout_base64']=='' and 'no declared NativeContext parameter' in rejected['stderr_utf8_preview'] and info.get('native_context_parameter_verified') is False and 'native_stats' not in info
    normal=out/'native-opt-out.php';normal.write_bytes(b"<?php var_dump(function_exists('dl_test_test2')); echo 'default';")
    reference=strict.run_process([str(php),'-n','-d','display_errors=stderr','-d','error_reporting=-1',str(normal)],out,30)
    actual=strict.run_process([str(ps),'-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(ROOT/'tools/differential/PhpCliCandidateWorker.ps1'),'-AdapterPath',str(candidate),'-SourcePath',str(normal)],out,30)
    diff=strict.differences(reference,actual)
    after={path:strict.sha256(Path(path)) for path in before}
    report={'status':'PASS' if guard and not diff and before==after else 'FAIL',
            'scope':'AST host parameter guard and NativeContext=null opt-out only; not PHP full conformance',
            'native_parameter_absent_rejected_before_source_or_module_execution':guard,
            'absent_parameter_result':rejected,'absent_parameter_metadata':info,
            'native_opt_out_matches_unextended_PHP':not diff,'opt_out_differences':diff,
            'opt_out_oracle':reference,'opt_out_candidate':actual,'inputs_before':before,'inputs_after':after,'inputs_unchanged':before==after}
    (out/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({key:report[key] for key in ['status','native_parameter_absent_rejected_before_source_or_module_execution','native_opt_out_matches_unextended_PHP','inputs_unchanged']}))
    return 0 if report['status']=='PASS' else 1


if __name__=='__main__':raise SystemExit(main())
