"""Inventory every PHPT file in the pinned PHP 8.5.12 test pack.

This does not execute tests, judge candidate behavior, or claim that PHPT is an
exhaustive PHP specification. Header matches are byte scans, not a PHPT runner.
"""
from pathlib import Path, PurePosixPath
from zipfile import ZipFile
from collections import Counter
import argparse
import base64
import datetime
import hashlib
import json
import re
import sys

PIN='79df191cab418a5277e7ad504143255c7b7ead06a2e6ebfa3b5b24503e94a519'
HEADER=re.compile(rb'^--([A-Z_]+)--[ \t]*\r?$',re.M)

def sha(data):return hashlib.sha256(data).hexdigest()

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--archive',type=Path,default=Path.home()/'Downloads/php-test-pack-8.5.12-1.zip')
    ap.add_argument('--source',type=Path,default=Path.home()/'ALL_php_oracle/php-8.5.12-tests')
    ap.add_argument('--output',type=Path,required=True)
    a=ap.parse_args();archive=a.archive.resolve(strict=True);source=a.source.resolve(strict=True);out=a.output.resolve()
    if out.exists():ap.error('Output exists; preserve it and use a fresh directory')
    if sha(archive.read_bytes())!=PIN:ap.error('Archive differs from the pinned PHP 8.5.12 test pack')
    disk={p.relative_to(source).as_posix():p for p in source.rglob('*.phpt') if p.is_file()}
    out.mkdir(parents=True)
    counts=Counter();headers=Counter();diff=[];seen=set();records=[]
    with ZipFile(archive) as z:
        entries=[i for i in z.infolist() if i.filename.lower().endswith('.phpt')]
        if len({i.filename for i in entries})!=len(entries):raise ValueError('Duplicate PHPT archive path')
        for i,entry in enumerate(sorted(entries,key=lambda e:e.filename)):
            name=entry.filename;logical=PurePosixPath(name)
            if logical.is_absolute() or '..' in logical.parts:raise ValueError('Unsafe archive path')
            raw=z.read(entry);digest=sha(raw);seen.add(name)
            local=disk.get(name);same=local is not None and local.read_bytes()==raw
            if not same:diff.append(name)
            matches=list(HEADER.finditer(raw))
            scanned=[{'name':m.group(1).decode('ascii'),'byte_offset':m.start()} for m in matches]
            for h in scanned:headers[h['name']]+=1
            area='/'.join(logical.parts[:2]) if logical.parts[0] in ('ext','Sapi') else logical.parts[0]
            counts[area]+=1
            title=None
            if matches and matches[0].group(1)==b'TEST':
                end=matches[1].start() if len(matches)>1 else len(raw)
                title=raw[matches[0].end():end]
            records.append({'id':'php8512-phpt:'+name,'archive_path':name,'source_path':str(source/name),
                            'source_matches_archive':same,'bytes':len(raw),'sha256':digest,'area':area,
                            'test_title_raw_base64':base64.b64encode(title).decode('ascii') if title is not None else None,
                            'header_scan_only':True,'observed_header_lines':scanned,
                            'candidate_state':'UNVERIFIED','oracle_executed':False,'candidate_executed':False})
            if (i+1)%2000==0:print(json.dumps({'inventoried':i+1,'total':len(entries)}),flush=True)
        runner=z.read('run-tests.php')
    extras=sorted(set(disk)-seen)
    if sha(archive.read_bytes())!=PIN:raise ValueError('Archive changed while read')
    rows=out/'upstream-phpt.jsonl'
    rows.write_text(''.join(json.dumps(r,ensure_ascii=False,separators=(',',':'))+'\n' for r in records),encoding='utf-8')
    (out/'run-tests.reference.php').write_bytes(runner)
    summary={'status':'SOURCE_INVENTORY_ONLY_NOT_COMPLETE','target':'PHP8.5.12 pinned test pack',
             'observed_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
             'archive':str(archive),'archive_sha256':PIN,'source_root':str(source),
             'archive_phpt_files':len(records),'disk_phpt_files':len(disk),'mismatched_or_missing':diff,'extra_disk_phpt':extras,
             'file_set_complete_and_hashes_match':not diff and not extras,
             'counts_by_area':dict(sorted(counts.items())),
             'header_line_scan_occurrences':dict(sorted(headers.items())),
             'header_scan_limitation':'Syntactic header-shaped lines only. FILEEOF/nested delimiters and PHPT execution semantics are not interpreted.',
             'manifest':rows.name,'manifest_sha256':sha(rows.read_bytes()),
             'official_runner_sha256':sha(runner),'driver_sha256':sha(Path(__file__).read_bytes()),
             'driver_argv':[sys.executable,*sys.argv],'all_candidate_states':'UNVERIFIED',
             'oracle_tests_executed':0,'candidate_tests_executed':0,'requirements_exhaustive':False,
             'compatibility_percentage':None,'scope':'No files excluded by extension, SAPI, INI, SKIPIF, OS, dependencies, feature support or old test results.'}
    (out/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:summary[k] for k in ['status','archive_phpt_files','disk_phpt_files','file_set_complete_and_hashes_match']}))
    return 0 if summary['file_set_complete_and_hashes_match'] else 1

if __name__=='__main__':raise SystemExit(main())
