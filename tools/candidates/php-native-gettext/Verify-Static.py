"""Independent PE/raw-input checks only. Does not load DLLs or run PHP."""
from pathlib import Path
import hashlib
import importlib.util
import json
import struct

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
REPORT=ROOT/'reports/php-native-gettext-20261113'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
read=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
save=lambda p,x:p.write_text(json.dumps(x,indent=2)+'\n',encoding='utf-8')

def main():
    destination=REPORT/'static-verification01.json';manifest_path=REPORT/'static-manifest01.json'
    assert not destination.exists()and not manifest_path.exists()
    spec=importlib.util.spec_from_file_location('static_pe',ROOT/'tools/abi/Inspect-NativeAbi.py');pe=importlib.util.module_from_spec(spec);spec.loader.exec_module(pe)
    inventory=read(REPORT/'inventory.json');extension=Path(inventory['binary']);assert sha(extension)==inventory['sha256']
    core_build=read(REPORT/'build-callback02/build.json');core=Path(core_build['candidate']);assert sha(core)==core_build['candidate_sha256']
    assert core_build['inputs_before']==core_build['inputs_after']
    for key in ['source','header','builder']:assert sha(Path(core_build['input_paths'][key]))==core_build['inputs_before'][key]
    generated=read(HERE/'generated03/provenance.json')
    for row in generated['inputs']:
        assert sha(Path(row['original']))==row['original_sha256']
        assert sha(Path(row['candidate']))==row['candidate_sha256']
        assert sha(Path(row['candidate']).with_suffix(Path(row['candidate']).suffix+'.patch'))==row['patch_sha256']
    for mode,row in inventory['current_info_v2_cores'].items():assert sha(Path(row['path']))==row['sha256']
    exports=pe.PE(core).exports();names={n for row in exports for n in row['names']};imports=pe.PE(core).imports()
    needed={s['name']for library in inventory['imports']if library['dll'].lower()=='php8ts.dll'for s in library['symbols']}
    assert not needed-names;assert not any(row.get('forwarder')for row in exports)
    assert not any(library['dll'].lower()in ['php8.dll','php8ts.dll']for library in imports)
    managed=read(HERE/'out/managed02/build.json');assert managed['inputs_before']==managed['inputs_after']
    for label,path in managed['input_paths'].items():assert sha(Path(path))==managed['inputs_before'][label]
    for row in managed['files']:assert sha(HERE/'out/managed02'/row['path'])==row['sha256']
    prepared=read(REPORT/'prepared01/prepared-manifest.json');assert prepared['timeout_seconds']==30and prepared['fixture_count']==51
    for relative,row in prepared['files'].items():assert sha(REPORT/'prepared01'/relative)==row['sha256']
    # Independent MO table decoding checks bytes written by the fixture builder.
    mo=REPORT/'prepared01/owned/catalog/zz_ALL/LC_MESSAGES/all_php_gettext_20261113.mo';data=mo.read_bytes();magic,revision,count,originals,translations,hash_size,hash_offset=struct.unpack_from('<7I',data)
    assert magic==0x950412de and revision==0 and count==3
    entries={}
    for i in range(count):
        a,b=struct.unpack_from('<2I',data,originals+8*i);c,d=struct.unpack_from('<2I',data,translations+8*i)
        assert data[b+a]==0and data[d+c]==0
        entries[data[b:b+a]]=data[d:d+c]
    assert entries[b'probe']==b'catalog-translated'and entries[b'apple\0apples']==b'catalog-one\0catalog-many'
    assert b'plural=(n != 1)'in entries[b'']
    record={'status':'STATIC_VERIFIED_NOT_LOADED_OR_RUNTIME_COMPATIBLE','extension_sha256':sha(extension),'candidate_core_sha256':sha(core),'source_sha256':core_build['inputs_before']['source'],'required_php8ts_names':sorted(needed),'missing_import_names':sorted(needed-names),'candidate_export_count':len(exports),'candidate_export_forwarders':[],'stock_core_imports':[],'unchanged_original_info_v2_inputs':True,'managed_build_inputs_unchanged':True,'frozen_fixtures':51,'frozen_timeout_seconds':30,'catalog_fixture_table_independently_decoded':True,'native_dll_loaded':False,'official_php_executed':False,'compatibility_pass_count':None,'new_builds_started':False,'large_sdk_read':False,'limits':['Import-name closure is not load or semantic compatibility.','No actual native or reference process was started.','UTF-8 Windows path behavior still requires reference comparisons.','Catalog payload existence is not observed translation.']}
    save(destination,record)
    files=[p for directory in [HERE,REPORT]for p in directory.rglob('*')if p.is_file()and p!=manifest_path and'__pycache__'not in p.parts]
    save(manifest_path,{'status':'FROZEN_STATIC_PREPARATION_NOT_RUNTIME','files':{p.relative_to(ROOT).as_posix():{'sha256':sha(p),'bytes':p.stat().st_size}for p in sorted(files)}})
    print(json.dumps({'status':record['status'],'manifest_files':len(files),'manifest_sha256':sha(manifest_path),'runtime_executed':False}))

if __name__=='__main__':main()
