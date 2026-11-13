"""Verify locale8 observations and native8+8 inputs without running native code."""
from pathlib import Path
import base64
import hashlib
import importlib.util
import json

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
LOCALE=ROOT/'reports/php-gettext-locale-20261113'
NATIVE=ROOT/'reports/php-native-gettext-20261113'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
read=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
save=lambda p,x:p.write_text(json.dumps(x,indent=2)+'\n',encoding='utf-8')

def main():
    target=LOCALE/'verification01.json';native_target=NATIVE/'controls8-preparation-verification01.json';assert not target.exists()and not native_target.exists()
    official=read(LOCALE/'oracle01/report.json');assert official['inputs_before']==official['inputs_after']and official['total']==8and official['candidate_execution_count']==0
    for path,pin in official['inputs_before'].items():assert sha(Path(path))==pin
    positive={'locale.language-nonC','locale.all-over-messages','locale.messages-over-lang','locale.lang-only','locale.language-fallback'}
    observations=[]
    for index,row in enumerate(official['records']):
        work=LOCALE/'oracle01'/(str(index).zfill(2)+'-'+row['id'])
        assert row['state']=='EXITED'and row['actual_exit_code']==0and row['parse_error']is None
        for channel in ['stdout','stderr']:assert sha(work/(channel+'.bin'))==row[channel+'_sha256']
        assert row['stderr_bytes']==0
        actual=json.loads((work/'stdout.bin').read_text());assert actual==row['observation']
        assert actual['environment_inside_php']==row['child_locale_environment']and row['locale_environment_snapshot_matches_php']
        assert actual['returned_CRT_locale']==actual['actual_CRT_locale_all']==actual['actual_CRT_locale_ctype']=='English_United States.utf8'
        translated=row['id']in positive
        assert base64.b64decode(actual['singular_base64'])==(b'catalog-translated'if translated else b'probe')
        assert base64.b64decode(actual['plural_base64'])==(b'catalog-many'if translated else b'apples')
        assert row['translation_observed']==translated
        observations.append({'id':row['id'],'translation_observed':translated,'effective_environment':row['child_locale_environment'],'actual_CRT_locale_all':actual['actual_CRT_locale_all'],'actual_exit_code':row['actual_exit_code'],'pid':row['pid']})
    save(target,{'status':'VERIFIED_OFFICIAL_ONLY_LOCALE_OBSERVATIONS_NOT_NATIVE_CONFORMANCE','observations':observations,'translations_observed':5,'negative_identity_controls':3,'locale5_environment_matches_php':True,'all_CRT_locale_requests_accepted_and_same_actual_English_locale':True,'source_inputs_and_copied_MO_unchanged':True,'candidate_execution_count':0,'historical51_environment_reconstructed':False})
    source=ROOT/'tools/candidates/php-native-gettext/Prepare-Profile.py'
    spec=importlib.util.spec_from_file_location('fixed_reference_verify',source);generator=importlib.util.module_from_spec(spec);spec.loader.exec_module(generator)
    native_profiles={}
    pins=read(HERE/'prepared-profile-pins.json');original_control={c['id']:c for c in read(LOCALE/'prepared01/controls.json')}
    for profile in ['value','catalog']:
        prep=NATIVE/(profile+'-controls8-prepared01');assert sha(prep/'prepared-manifest.json')==pins[profile]
        manifest=read(prep/'prepared-manifest.json');assert manifest['fixture_count']==8and manifest['timeout_seconds']==30
        for relative,row in manifest['files'].items():assert sha(prep/relative)==row['sha256']
        provenance=read(prep/'provenance.json')
        assert sha(Path(provenance['core']))==provenance['core_sha256']=='96df49fe6a7dd83c3462c2b92d0b14922e0f292b2cf80212e47242a8932fdef3'
        assert sha(Path(provenance['reference_generator']))==provenance['reference_generator_sha256']
        assert sha(Path(provenance['comparator']))==provenance['comparator_sha256']
        fixtures=[read(p)for p in sorted((prep/'cases').glob('*/fixture.json'))]
        for fixture in fixtures:
            assert (prep/'cases'/fixture['id']/'reference.php').read_text()==generator.reference(fixture)
            if profile=='catalog':
                control=original_control[fixture['source_oracle_control_id']]
                assert fixture['expected_effective_locale_environment']==control['environment_overrides']
                assert fixture['env']=={k:v for k,v in control['environment_overrides'].items()if v is not None}
                assert sha(Path(fixture['catalog_mo_input']))==fixture['catalog_mo_sha256']=='a8aa43b7c0fc2c43da96a6e6526952fe508ed42d19ef0a18698e800711643dad'
                assert [s['operation']for s in fixture['steps']]==['locale','call','call','call']
                assert [s['function']for s in fixture['steps'][1:]]==['bindtextdomain','dgettext','dngettext']
                if fixture['source_oracle_control_id']in positive:
                    assert base64.b64decode(fixture['required_last_translation_base64'])==b'catalog-many'
                    assert base64.b64decode(fixture['required_singular_translation_base64'])==b'catalog-translated'
                else:assert fixture['negative_identity_control']and'required_last_translation_base64'not in fixture
        if profile=='value':assert sum(f['steps'][0]['strict']for f in fixtures)==6and sum(not f['steps'][0]['strict']for f in fixtures)==2
        native_profiles[profile]={'fixtures':8,'manifest_sha256':sha(prep/'prepared-manifest.json'),'reference_source_regenerated_exactly':True,'native_execution_count':0}
    save(native_target,{'status':'VERIFIED_PREPARATION_NOT_NATIVE_EXECUTION','profiles':native_profiles,'core_sha256':'96df49fe6a7dd83c3462c2b92d0b14922e0f292b2cf80212e47242a8932fdef3','host_sha256':'a94faefa8bed3d9006cfb362b3812d1c86fd6b68d3ec80540f5c33300e5e2ba6','wrapper_sha256':sha(HERE/'Compare-NativeControls.py'),'old51_expected_values_changed':False,'deadline_seconds':30,'comparison_function_changed':False,'catalog_environment_setup_is_explicit_new_profile':True,'root_runtime_start_signal_pending':True})
    paths=[p for folder in [LOCALE,HERE,ROOT/'tools/candidates/php-gettext-locale',NATIVE/'value-controls8-prepared01',NATIVE/'catalog-controls8-prepared01']for p in folder.rglob('*')if p.is_file()and'__pycache__'not in p.parts]+[native_target]
    artifact=LOCALE/'preparation-and-oracle-manifest01.json';assert not artifact.exists();save(artifact,{'status':'OWNED_LOCALE_ORACLE_AND_NEW_NATIVE_PREPARATION','files':{p.relative_to(ROOT).as_posix():{'sha256':sha(p),'bytes':p.stat().st_size}for p in sorted(set(paths))}})
    print(json.dumps({'locale_observations':8,'actual_translations':5,'identity_controls':3,'native_profiles_prepared':16,'native_executed':0,'manifest_sha256':sha(artifact)}))

if __name__=='__main__':main()
