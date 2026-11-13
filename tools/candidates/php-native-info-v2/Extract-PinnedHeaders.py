"""Copy only already-approved SDK headers into a fresh owned directory."""
from pathlib import Path
import hashlib
import json
import zipfile

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
archive=Path('C:/Users/rinpa/Downloads/php-devel-pack-8.5.12-1-Win32-vs17-x64.zip')
pin='52cb020402c3165e7cb37ec0d96ae43e26997f01d0fdb5474aa92801246810e9'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(archive)==pin
destination=HERE/'sdk/sdk01';assert not destination.exists();destination.mkdir(parents=True)
files=[]
with zipfile.ZipFile(archive)as source:
 for info in source.infolist():
  normalized=info.filename.replace('\\','/')
  if info.is_dir()or'/include/'not in normalized:continue
  target=(destination/normalized).resolve()
  assert target.is_relative_to(destination.resolve()),info.filename
  target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(source.read(info))
  files.append({'member':info.filename,'path':target.relative_to(ROOT).as_posix(),'bytes':target.stat().st_size,'sha256':sha(target)})
assert files
sdk=next(p.parent.parent for p in destination.rglob('zend_modules.h')if p.parent.name=='Zend')
record={'status':'APPROVED_HEADER_ARCHIVE_COPIED_NO_INSTALL_OR_RUNTIME_EXECUTION','archive':str(archive),'archive_sha256':pin,'sdk_include_directory':str(sdk),'files':files}
report=ROOT/'reports/php-native-info-v2-20261113/sdk-preparation01';report.mkdir(parents=True)
(report/'headers.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'headers':len(files),'include':str(sdk),'archive_unchanged':sha(archive)==pin}))
