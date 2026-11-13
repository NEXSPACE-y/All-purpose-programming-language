"""Freeze gettext programs, raw values and local MO catalog without execution."""
from pathlib import Path
import argparse
import base64
import hashlib
import json
import struct

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
save=lambda p,x:p.write_text(json.dumps(x,indent=2)+'\n',encoding='utf-8')
B=lambda x:{'type':'bytes','base64':base64.b64encode(x if isinstance(x,bytes)else x.encode()).decode()}
I=lambda x:{'type':'int','value':str(x)}
N={'type':'null'}

def php_argument(value):
    kind=value['type']
    if kind=='bytes':return "base64_decode('"+value['base64']+"')"
    if kind=='int':return "(int)'"+value['value']+"'"
    if kind=='null':return 'null'
    if kind=='bool':return 'true'if value['value']else'false'
    if kind=='double':return value['value']
    raise ValueError(kind)

def reference(fixture):
    strict={step['strict']for step in fixture['steps']if step['operation']=='call'}
    assert len(strict)<=1
    lines=['<?php','declare(strict_types='+('1'if True in strict else'0')+');',r'''
function all_value($value){return is_string($value)?['type'=>'string','value'=>base64_encode($value)]:(is_int($value)?['type'=>'int','value'=>(string)$value]:(is_null($value)?['type'=>'null','value'=>null]:['type'=>get_debug_type($value),'value'=>$value]));}
$observations=[];$events=[];
set_error_handler(function($level,$message)use(&$events){$events[]=['level'=>$level,'message_base64'=>base64_encode($message)];return true;});
''']
    for step in fixture['steps']:
        op=step['operation']
        if op=='call':
            name=step['function'];assert name.replace('_','').isalnum()or name=='_'
            call=name+'('+','.join(php_argument(v)for v in step['args'])+')'
            lines.append("$events=[];$row=['operation'=>'call','function'=>'"+name+"','ok'=>true,'value'=>all_value(null),'error_class'=>null,'error_message_base64'=>null];ob_start();try{$row['value']=all_value("+call+");}catch(Throwable $e){$row['ok']=false;$row['error_class']=get_class($e);$row['error_message_base64']=base64_encode($e->getMessage());}$output=ob_get_clean();echo $output;$row['output_base64']=base64_encode($output);$row['events']=$events;$observations[]=$row;")
        elif op=='locale':
            lines.append('$locale=setlocale('+str(step['category'])+','+php_argument(B(step['locale']))+");$observations[]=['operation'=>'locale','accepted'=>$locale!==false,'locale'=>$locale===false?null:$locale];")
        elif op=='virtual_cwd':
            lines.append('if(!chdir('+php_argument({'type':'bytes','base64':step['base64']})+"))throw new RuntimeException('Owned fixture chdir failed');$observations[]=['operation'=>'virtual_cwd','value'=>all_value(getcwd())];")
        elif op=='get_cwd':lines.append("$observations[]=['operation'=>'get_cwd','value'=>all_value(getcwd())];")
        elif op=='module_info':lines.append("ob_start();(new ReflectionExtension('gettext'))->info();$output=ob_get_clean();echo $output;$observations[]=['operation'=>'module_info','output_base64'=>base64_encode($output)];")
        else:raise ValueError(op)
    lines.append("file_put_contents($argv[1],json_encode(['observations'=>$observations],JSON_THROW_ON_ERROR));")
    return '\n'.join(lines)+'\n'

def catalog(entries):
    entries=sorted(entries.items());count=len(entries);offset=28+16*count
    original=b'';translations=b'';originals=[];translated=[]
    for key,value in entries:originals.append((len(key),offset+len(original)));original+=key+b'\0'
    translated_offset=offset+len(original)
    for key,value in entries:translated.append((len(value),translated_offset+len(translations)));translations+=value+b'\0'
    return struct.pack('<7I',0x950412de,0,count,28,28+8*count,0,0)+b''.join(struct.pack('<2I',*v)for v in originals+translated)+original+translations

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',type=Path,required=True);args=parser.parse_args();out=args.output.resolve()
    assert out.is_relative_to(ROOT/'reports/php-native-gettext-20261113')and not out.exists();out.mkdir(parents=True)
    owned=out/'owned';owned.mkdir();(owned/'plain').mkdir();(owned/'日本語').mkdir();(owned/'file.txt').write_bytes(b'owned gettext path fixture\n')
    domain='all_php_gettext_20261113';mo=owned/'catalog/zz_ALL/LC_MESSAGES'/ (domain+'.mo');mo.parent.mkdir(parents=True)
    mo.write_bytes(catalog({b'':b'Content-Type: text/plain; charset=UTF-8\nLanguage: zz_ALL\nPlural-Forms: nplurals=2; plural=(n != 1);\n',b'probe':b'catalog-translated',b'apple\0apples':b'catalog-one\0catalog-many'}))
    cases=[]
    def add(identity,group,function=None,arguments=(),strict=False,steps=None,**extra):
        row={'id':identity,'group':group,'steps':steps if steps is not None else[{'operation':'call','function':function,'args':list(arguments),'strict':strict}]};row.update(extra);cases.append(row)
    for identity,data in [('ascii',b'untranslated-all-php'),('empty',b''),('rawFF',b'A\xffB'),('embeddedNUL',b'A\0B'),('surrogateUTF8',bytes.fromhex('eda080')),('all256',bytes(range(256))),('limit4096',b'x'*4096)]:add('identity.'+identity,'untranslated_identity','gettext',[B(data)])
    add('identity.alias','untranslated_identity','_',[B(b'alias\xff\0tail')])
    for count in [0,1,2,-1]:add('plural.'+str(count),'untranslated_plural','ngettext',[B('apple'),B('apples'),I(count)])
    add('plural.rawNUL','untranslated_plural','ngettext',[B(b'a\0tail'),B(b'b\0tail'),I(2)])
    add('domain.getter','domain_state','textdomain',[])
    add('domain.null','domain_state','textdomain',[N])
    add('domain.setter','domain_state','textdomain',[B(domain)])
    add('domain.empty','domain_state','textdomain',[B('')])
    add('domain.raw','domain_state','dgettext',[B(b'dom\xff'),B(b'id\xff\0tail')])
    add('domain.NUL','domain_state','dgettext',[B(b'dom\0tail'),B('id')])
    add('domain.max1024','domain_state','dgettext',[B('x'*1024),B('id')])
    for identity,fn,values in [('gettext-long','gettext',[B('x'*4097)]),('dgettext-empty','dgettext',[B(''),B('id')]),('dgettext-long','dgettext',[B('x'*1025),B('id')]),('bind-empty','bindtextdomain',[B('')]),('category-all','dcgettext',[B(domain),B('id'),I(0)]),('plural-category-all','dcngettext',[B(domain),B('one'),B('many'),I(2),I(0)]),('bind-domain-NUL','bindtextdomain',[B(b'dom\0tail')]),('bind-dir-NUL','bindtextdomain',[B(domain),B(b'plain\0tail')])]:add('error.'+identity,'argument_diagnostics',fn,values)
    for identity,fn,values,strict in [('few','gettext',[],False),('many','gettext',[B('a'),B('b')],False),('weak-int','gettext',[I(42)],False),('strict-int','gettext',[I(42)],True),('null','gettext',[N],False),('plural-weak','ngettext',[B('one'),B('many'),B('2')],False),('plural-strict','ngettext',[B('one'),B('many'),B('2')],True),('nullable-invalid','textdomain',[{'type':'bool','value':True}],True)]:add('type.'+identity,'argument_diagnostics',fn,values,strict)
    for identity,path in [('current-empty',''),('current-zero','0'),('dot','.'),('relative','plain'),('unicode','日本語'),('absolute',str(owned/'plain')),('missing','not-existing'),('file','file.txt'),('parent','plain/..')]:
        add('path.'+identity,'owned_path','bindtextdomain',[B(domain),B(path)],cwd=str(owned))
    add('path.virtual-isolation','owned_path',steps=[{'operation':'virtual_cwd','base64':B(str(owned/'日本語'))['base64']},{'operation':'get_cwd'},{'operation':'call','function':'bindtextdomain','args':[B(domain),B('0')],'strict':False}],cwd=str(owned))
    add('codeset.query','codeset','bind_textdomain_codeset',[B(domain)])
    add('codeset.set','codeset','bind_textdomain_codeset',[B(domain),B('UTF-8')])
    add('gettext.module-info','module_info',steps=[{'operation':'module_info'}])
    for identity,fn,values,expected in [('singular','dgettext',[B(domain),B('probe')],b'catalog-translated'),('plural','dngettext',[B(domain),B('apple'),B('apples'),I(2)],b'catalog-many')]:
        add('catalog.'+identity,'catalog_translation',steps=[{'operation':'locale','category':0,'locale':'English_United States.utf8'},{'operation':'call','function':'bindtextdomain','args':[B(domain),B(str(owned/'catalog'))],'strict':False},{'operation':'call','function':fn,'args':values,'strict':False}],env={'LANGUAGE':'zz_ALL'},required_last_translation_base64=B(expected)['base64'])
    fixture_dir=out/'cases';fixture_dir.mkdir()
    for case in cases:
        (fixture_dir/case['id']).mkdir();folder=fixture_dir/case['id'];save(folder/'fixture.json',case);(folder/'reference.php').write_text(reference(case),encoding='utf-8',newline='\n')
    paths=[p for p in out.rglob('*')if p.is_file()];manifest={p.relative_to(out).as_posix():{'sha256':sha(p),'bytes':p.stat().st_size}for p in sorted(paths)}
    save(out/'prepared-manifest.json',{'status':'FROZEN_INPUTS_NOT_EXECUTED','fixture_count':len(cases),'timeout_seconds':30,'groups':{group:sum(c['group']==group for c in cases)for group in sorted({c['group']for c in cases})},'source':str(Path(__file__).resolve()),'source_sha256':sha(Path(__file__).resolve()),'files':manifest,'catalog_translation_is_not_identity':True,'os_locale_installed_or_machine_wide_changed':False})
    print(json.dumps({'directory':str(out),'case_count':len(cases),'manifest_sha256':sha(out/'prepared-manifest.json'),'executed':False}))

if __name__=='__main__':main()
