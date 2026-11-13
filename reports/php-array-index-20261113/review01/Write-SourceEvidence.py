"""Pin fixed official source excerpts and frozen reviewed candidate inputs."""
from pathlib import Path
import zipfile,hashlib,json
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2];archive=Path.home()/'Downloads/php-8.5.12-1-src.zip';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(archive)=='9dac05f72f328afd0a2b0e795a519ae4cb3d056bc3f3b55147bd048bd64e45e8'
reviewed=ROOT/'tools/candidates/php-byte-interpreter/composed12-index/ALL_PHP_byte_candidate.ps1';module=reviewed.parent/'module-snapshots/ArrayIndexEdits.py';assert sha(reviewed)=='79e39d1e05d2813e9c593b0761409075cb9bd87930907b5c560434e0c2f3f827'
items=[]
with zipfile.ZipFile(archive) as z:
 ranges={'Zend/zend_hash.c':[(282,307),(1273,1289),(1370,1379),(1427,1445),(2671,2690),(2699,2725)],'ext/standard/array.c':[(3604,3609),(3625,3634),(3650,3664),(3675,3681),(3732,3736),(3760,3782),(3796,3813),(3815,3837)],'Zend/zend_API.h':[(2168,2187)],'Zend/zend_execute.c':[(2592,2595)],'Zend/zend_compile.c':[(3563,3586)]}
 for name,spans in ranges.items():
  raw=z.read(name);lines=raw.decode('utf-8').splitlines()
  items.append({'entry':name,'entry_sha256':hashlib.sha256(raw).hexdigest(),'excerpts':[{'start_line':a,'end_line':b,'text':'\n'.join(lines[a-1:b])} for a,b in spans]})
inputs={}
for name,path in {'candidate':reviewed,'candidate_module_snapshot':module,'original18':ROOT/'tools/candidates/php-byte-interpreter/array-index.cases.json','original_edges14':ROOT/'tools/candidates/php-byte-interpreter/array-index-edges.cases.json','original18_observations':ROOT/'reports/php-array-index-20261113/oracle01/report.json','original14_observations':ROOT/'reports/php-array-index-20261113/oracle-edges01/report.json'}.items():inputs[name]={'path':str(path),'sha256':sha(path)}
(HERE/'source-evidence.json').write_text(json.dumps({'scope':'Official source reading only; no implementation copied into the interpreter; no candidate execution','archive':str(archive),'archive_sha256':sha(archive),'reviewed_inputs':inputs,'evidence':items},indent=2)+'\n',encoding='utf-8');print(json.dumps({'archive_sha256':sha(archive),'entries':len(items),'reviewed_module_sha256':sha(module),'reviewed_candidate_sha256':sha(reviewed)}))
