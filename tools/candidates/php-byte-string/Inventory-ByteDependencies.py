"""Pinned source dependency inventory; static occurrences are review candidates, not changed code."""
from pathlib import Path
import re,hashlib,json,argparse

ROOT=Path(__file__).resolve().parents[3]
ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--output',type=Path,required=True);ap.add_argument('--adapter',type=Path,default=ROOT/'tools/candidates/php-cli-host/base113d.snapshot.ps1');a=ap.parse_args()
if a.output.exists():raise SystemExit('Preserve existing inventory')
if hashlib.sha256(a.adapter.read_bytes()).hexdigest()!='113d0c2b967a8726cd9a9dec3f032a725ed9c98ee093c4aedd0a4830737f155b':raise SystemExit('Pinned113d adapter input differs')
paths=[a.adapter.resolve(),ROOT/'tools/abi/AllNativeBridge.cs',ROOT/'package/ALL_cli.ps1',
       ROOT/'package/run.ps1',ROOT/'package/ALL_linux_core.ps1',ROOT/'package/ALL_v1_0_adapter.ps1',
       ROOT/'tools/candidates/php-native-callback/AllNativeCallbackBridge.cs',ROOT/'native/php85abi/src/Runtime.cpp']
patterns={'string_type_or_cast':r'\[string\]|\bis string\b','text_codec':r'Encoding|UTF8|GetString|GetBytes|ReadAllText|WriteAllText',
          'text_operations':r'\.Substring\(|\.IndexOf\(|\.ToLowerInvariant\(|\.ToUpperInvariant\(|StringComparison|StringComparer',
          'text_output':r'Console\]::Write|Console\.Write|WriteAllText|To-PhpText',
          'string_key_encoding':r"'s:'|\"s:|To-PhpKey|OrderedDictionary|ConvertFrom-PhpNumericString"}
files=[]
for path in paths:
    if not path.exists():continue
    raw=path.read_bytes();text=raw.decode('utf-8-sig');function='(top level)';occurrences=[]
    for line_number,line in enumerate(text.splitlines(),1):
        m=re.match(r'\s*function\s+([\w-]+)',line)
        if m:function=m.group(1)
        kinds=[name for name,pattern in patterns.items() if re.search(pattern,line)]
        if kinds:occurrences.append({'line':line_number,'enclosing_function_heuristic':function,'kinds':kinds,'source':line.strip()})
    files.append({'path':path.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(raw).hexdigest(),'lines':len(text.splitlines()),'occurrences':occurrences,'counts':{key:sum(key in row['kinds'] for row in occurrences) for key in patterns}})
result={'status':'STATIC_DEPENDENCY_REVIEW_ONLY','base_adapter_sha256':files[0]['sha256'],'method':'Line-pattern inventory; function labels are a heuristic, not full AST/dataflow analysis. Identifiers and user string values must be reviewed separately.','files':files}
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({f['path']:f['counts'] for f in files}))
