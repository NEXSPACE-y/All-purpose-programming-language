"""Freeze the actual pre-symbol candidate and selected symbol source revision."""
from pathlib import Path
import argparse,hashlib,importlib.util,json,sys,difflib
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--base',type=Path,required=True);ap.add_argument('--expected-base',required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
 out=a.output.resolve()
 if out.exists():ap.error('Choose fresh revision output')
 base=a.base.resolve(strict=True);module=ROOT/'tools/candidates/php-byte-interpreter/SymbolEdits.py'
 if digest(base)!=a.expected_base:ap.error('Starting candidate hash mismatch')
 before=base.read_bytes();module_bytes=module.read_bytes();spec=importlib.util.spec_from_file_location('symbol_edits',module);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
 text=before.decode('utf-8-sig');after=m.apply(text)
 assert after.replace('\r\n','\n')==m.apply(text.replace('\r\n','\n'))
 assert before==base.read_bytes() and module_bytes==module.read_bytes()
 out.mkdir(parents=True);(out/'base.snapshot.ps1').write_bytes(before);(out/'SymbolEdits.snapshot.py').write_bytes(module_bytes)
 candidate=out/'ALL_PHP_symbol_candidate.ps1';candidate.write_bytes(b'\xef\xbb\xbf'+after.encode('utf-8'))
 (out/'source.patch').write_text(''.join(difflib.unified_diff(text.splitlines(True),after.splitlines(True),fromfile='pre-symbol-frozen',tofile='symbol-candidate')),encoding='utf-8',newline='')
 (out/'provenance.json').write_text(json.dumps({'status':'BUILT_NOT_RUNTIME_VERIFIED','base':str(base),'base_sha256':digest(base),'module':str(module),'module_sha256':digest(module),'builder_sha256':digest(Path(__file__).resolve()),'candidate_sha256':digest(candidate),'crlf_retained':after.count('\r\n')==after.count('\n'),'lf_composition_same':True,'package_modified':False,'runtime_delegation':False,'scope':'Valid-UTF8 metadata/lexer bridge; raw byte names/source decoder not adopted'},indent=2)+'\n',encoding='utf-8')
 print(json.dumps({'candidate':str(candidate),'sha256':digest(candidate)}))
if __name__=='__main__':main()
