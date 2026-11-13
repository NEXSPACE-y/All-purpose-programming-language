"""Copy the frozen info-v2 build recipe into this isolated profile."""
from pathlib import Path
import hashlib
import json

HERE=Path(__file__).resolve().parent
BASE=HERE.parent/'php-native-info-v2'
source=BASE/'Build-Core.ps1'
destination=HERE/'Build-Core.ps1'
assert not destination.exists()
value=source.read_text(encoding='utf-8-sig').replace('all_php85abi_info_v2.lib','all_php85abi_gettext.lib').replace('Info v2 core','Gettext core')
destination.write_text(value,encoding='utf-8',newline='\n')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
(HERE/'builder-provenance.json').write_text(json.dumps({'original':str(source),'original_sha256':sha(source),'candidate':str(destination),'candidate_sha256':sha(destination),'changes':['new output import-library name','diagnostic label only'],'runtime_executed':False},indent=2)+'\n',encoding='utf-8')
