"""Create separate bool8/catalog8 inputs using the frozen reference generator."""
from pathlib import Path
import hashlib
import importlib.util
import json

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
NATIVE=ROOT/'tools/candidates/php-native-gettext'
REPORT=ROOT/'reports/php-native-gettext-20261113'
LOCALE=ROOT/'reports/php-gettext-locale-20261113/prepared01'
GENERATOR=NATIVE/'Prepare-Profile.py'
COMPARATOR=NATIVE/'Compare-Gettext05.py'
CORE=NATIVE/'out/callback05/php8ts.dll'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
save=lambda p,x:p.write_text(json.dumps(x,indent=2)+'\n',encoding='utf-8')
assert sha(CORE)=='96df49fe6a7dd83c3462c2b92d0b14922e0f292b2cf80212e47242a8932fdef3'
spec=importlib.util.spec_from_file_location('fixed_reference',GENERATOR);generator=importlib.util.module_from_spec(spec);spec.loader.exec_module(generator)
bool_cases=[]
for truth in [True,False]:
    argument={'type':'bool','value':truth};label='true'if truth else'false'
    for function,arguments in [('gettext',[argument]),('textdomain',[argument]),('ngettext',[generator.B('one'),generator.B('many'),argument])]:
        bool_cases.append({'id':'value.strict.'+function+'.'+label,'group':'strict_bool_value_diagnostic','steps':[{'operation':'call','function':function,'args':arguments,'strict':True}]})
    bool_cases.append({'id':'value.weak.gettext.'+label,'group':'weak_bool_coercion','steps':[{'operation':'call','function':'gettext','args':[argument],'strict':False}]})
locale_controls=json.loads((LOCALE/'controls.json').read_text());locale_provenance=json.loads((LOCALE/'provenance.json').read_text())
assert sha(LOCALE/'manifest.json')=='8c96bdfd924e005cdec3b689482810be908c78d0b883ecb6f640816750856a4e'
mo=Path(locale_provenance['copied_mo']);assert sha(mo)=='a8aa43b7c0fc2c43da96a6e6526952fe508ed42d19ef0a18698e800711643dad'
catalog=mo.parents[2];domain=mo.stem
positive={'locale.language-nonC','locale.all-over-messages','locale.messages-over-lang','locale.lang-only','locale.language-fallback'}
catalog_cases=[]
for control in locale_controls:
    identity=control['id'];environment=control['environment_overrides']
    fixture={'id':'catalog-control.'+identity,'group':'catalog_translation_positive'if identity in positive else'negative_identity_control','env':{k:v for k,v in environment.items()if v is not None},'expected_effective_locale_environment':environment,'source_oracle_control_id':identity,'catalog_mo_input':str(mo),'catalog_mo_sha256':sha(mo),'steps':[{'operation':'locale','category':0,'locale':'English_United States.utf8'},{'operation':'call','function':'bindtextdomain','args':[generator.B(domain),generator.B(str(catalog))],'strict':False},{'operation':'call','function':'dgettext','args':[generator.B(domain),generator.B('probe')],'strict':False},{'operation':'call','function':'dngettext','args':[generator.B(domain),generator.B('apple'),generator.B('apples'),generator.I(2)],'strict':False}]}
    if identity in positive:
        fixture['required_last_translation_base64']=generator.B('catalog-many')['base64'];fixture['required_singular_translation_base64']=generator.B('catalog-translated')['base64']
    else:fixture['negative_identity_control']=True
    catalog_cases.append(fixture)
for profile,cases in [('value',bool_cases),('catalog',catalog_cases)]:
    out=REPORT/(profile+'-controls8-prepared01');assert not out.exists();out.mkdir()
    folder=out/'cases';folder.mkdir()
    for fixture in cases:
        target=folder/fixture['id'];target.mkdir();save(target/'fixture.json',fixture);(target/'reference.php').write_text(generator.reference(fixture),encoding='utf-8',newline='\n')
    provenance={'status':'NEW_PROFILE_NOT_EXECUTED','profile':profile,'core':str(CORE),'core_sha256':sha(CORE),'managed_build':str(NATIVE/'out/managed02'),'reference_generator':str(GENERATOR),'reference_generator_sha256':sha(GENERATOR),'comparator':str(COMPARATOR),'comparator_sha256':sha(COMPARATOR),'preparer':str(Path(__file__).resolve()),'preparer_sha256':sha(Path(__file__).resolve()),'original51_manifest':str(REPORT/'prepared01/prepared-manifest.json'),'original51_manifest_sha256':sha(REPORT/'prepared01/prepared-manifest.json'),'fixtures':len(cases),'timeout_seconds':30,'candidate_execution_count':0,'comparison_function_or_deadline_changed':False,'catalog_wrapper_environment_contract':'Remove locale5 keys inside wrapper process before original comparator; each fixture restores nonnull keys to reproduce oracle8 exact absent/nonempty environment.'if profile=='catalog'else'No environment change; same inherited profile as original51.'}
    if profile=='catalog':provenance.update({'copied_mo':str(mo),'copied_mo_sha256':sha(mo),'independent_locale_manifest':str(LOCALE/'manifest.json'),'independent_locale_manifest_sha256':sha(LOCALE/'manifest.json'),'positive_translation_controls':5,'negative_identity_controls':3})
    save(out/'provenance.json',provenance)
    files=[p for p in out.rglob('*')if p.is_file()]
    save(out/'prepared-manifest.json',{'status':'NEW_FROZEN_INPUTS_NOT_EXECUTED','fixture_count':len(cases),'timeout_seconds':30,'files':{p.relative_to(out).as_posix():{'sha256':sha(p),'bytes':p.stat().st_size}for p in sorted(files)}})
    print(json.dumps({'profile':profile,'cases':len(cases),'manifest_sha256':sha(out/'prepared-manifest.json'),'executed':False}))
