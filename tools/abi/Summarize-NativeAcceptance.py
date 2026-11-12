#!/usr/bin/env python3
"""Summarise actual native-worker/reference results; never execute PHP or DLLs."""
from __future__ import annotations
import argparse
import datetime as dt
import hashlib
import importlib.util
import json
from pathlib import Path
import sys


def read(path): return json.loads(path.read_text(encoding="utf-8-sig"))
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root",type=Path,default=Path(__file__).resolve().parents[2])
    args=parser.parse_args();root=args.root.resolve();out=root/"reports/native-abi-implementation-20261112"
    sys.dont_write_bytecode=True
    spec=importlib.util.spec_from_file_location("all_pe_inspector",root/"tools/abi/Inspect-NativeAbi.py")
    pe=importlib.util.module_from_spec(spec);spec.loader.exec_module(pe)
    inventory=read(root/"reports/native-abi-20261112/pe-inventory.json")
    build=read(out/"build.json");candidate=Path(build["candidate"])
    core=pe.PE(candidate);exports=core.exports();export_names={n for e in exports for n in e["names"]}
    imports=core.imports()
    checks={"candidate_hash_matches_build":digest(candidate)==build["candidate_sha256"],
            "candidate_source_hash_matches_build":digest(root/"native/php85abi/src/Runtime.cpp")==build["source_sha256"],
            "candidate_does_not_import_stock_PHP":not any(g["dll"].lower().startswith("php") for g in imports)}
    comparisons=[];thread_records=[];metadata_records=[];unique_case_ids=set()
    for mode,suffix in [("normal",""),("legacy","legacy-")]:
        actual=read(out/("candidate-"+suffix+"worker.json"));expected=read(out/("oracle-"+suffix+"worker.json"))
        reference={r["id"]:r["result"] for r in expected["cases"]}
        checks[mode+"_same_case_ids"]=set(reference)=={r["id"] for r in actual["cases"]}
        for row in actual["cases"]:
            unique_case_ids.add(row["id"])
            wanted=reference[row["id"]];got=row["result"]
            differences={key:{"actual":got.get(key),"expected":wanted.get(key)} for key in set(got)|set(wanted) if got.get(key)!=wanted.get(key)}
            comparisons.append({"mode":mode,"id":row["id"],"matched":not differences,"differences":differences})
        a=actual["metadata"];b=expected["metadata"]
        fields=["constant","parent","property","inherited_property","ini_long","ini_string","ini_changed"]
        if mode=="legacy":fields.append("direct_registration")
        metadata_records.append({"mode":mode,"kind":"native_registration_metadata_and_INI_inspection_not_property_execution",
                                 "matches":{field:a.get(field)==b.get(field) for field in fields}})
        php_cores=[Path(p) for p in a["loaded_php_modules"] if Path(p).name.lower()=="php8ts.dll"]
        checks[mode+"_only_loaded_PHP_core_is_own_candidate"]=len(php_cores)==1 and str(php_cores[0]).lower()==str(candidate).lower()
        checks[mode+"_reported_core_path_matches"]=str(a["core_path"]).lower()==str(candidate).lower()
        checks[mode+"_INI_resets_at_next_request"]=a["ini_reset"]==["0","hello"]
        mem=a["memory_probe"]
        checks[mode+"_memory_refcount_and_owner_probe"]=mem["before"]==mem["after"] and mem["retained_refcount"]==2 and mem["remaining_refcount"]==1 and mem["cross_thread_free_rejected"] and mem["owner_buffer_intact"]
        for i,t in enumerate(actual["thread_isolation"]):
            expected_value=__import__("base64").b64encode(("Hello thread"+str(i)).encode()).decode()
            good=t["Error"] is None and t["Before"]=="0" and t["After"]=="0" and t["Value"]==str(100+i) and t["Call"]["Ok"] and t["Call"]["Value"]==expected_value
            thread_records.append({"mode":mode,"thread":i,"matched":good})
        stats=actual["stats_after_shutdown"]
        checks[mode+"_controlled_lifecycle_balanced"]=stats["minit"]==stats["mshutdown"]==1 and stats["rinit"]==stats["rshutdown"]==6 and stats["tls_contexts_created"]==stats["tls_contexts_destroyed"]==3
        checks[mode+"_tracked_request_allocations_zero"]=stats["request_allocations_live"]==0
    original=next(i for i in inventory["images"] if i["relative_path"]=="ext/php_dl_test.dll")
    checks["original_dl_test_binary_hash_preserved"]=digest(Path(original["path"]))==original["sha256"]
    rejected=read(out/"unsupported-module-load.json")
    checks["unsupported_module_load_rejected"]=rejected["status"]=="LOAD_REJECTED"
    scalar=read(out/"scalar-bridge-contract.json")
    checks["scalar_bridge_contract_checks_pass"]=scalar["all_passed"] and all(scalar["checks"].values())
    matrix=[]
    for image in inventory["images"][1:]:
        required={s.get("name",f"ordinal:{s.get('ordinal')}") for group in image["imports"] if group["dll"].lower()=="php8ts.dll" for s in group["symbols"]}
        present=sorted(required&export_names);missing=sorted(required-export_names)
        matrix.append({"module":image["module"].get("name"),"path":image["relative_path"],
                       "required_php_symbols":len(required),"present_symbol_names":present,"missing_symbol_names":missing,
                       "runtime_status":"SELECTED_CALL_CASES_VERIFIED_IN_TWO_MODES_NOT_FULL_MODULE_COMPATIBILITY" if image["relative_path"]=="ext/php_dl_test.dll" else "NOT_VERIFIED",
                       "all_symbol_names_present_is_not_a_semantic_pass":True})
    (out/"remaining-symbol-contracts.json").write_text(json.dumps(matrix,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    success=all(checks.values()) and all(c["matched"] for c in comparisons) and all(r["matched"] for r in thread_records) and all(all(r["matches"].values()) for r in metadata_records)
    report={"schema_version":1,"generated_at_utc":dt.datetime.now(dt.timezone.utc).isoformat(),
            "status":"SELECTED_NATIVE_ACCEPTANCE_PASS" if success else "NATIVE_ACCEPTANCE_HAS_FAILURES",
            "owner_option_A_approved":True,"broader_option_B_adopted":False,
            "candidate":str(candidate),"candidate_sha256":digest(candidate),
            "original_extension_sha256":original["sha256"],"method":"unchanged_native_extension_in_isolated_ALL_worker_vs_separate_stock_PHP_reference",
            "unique_call_cases":len(unique_case_ids),"call_comparisons":len(comparisons),"matched_call_comparisons":sum(c["matched"] for c in comparisons),
            "checks":checks,"call_results":comparisons,"thread_results":thread_records,"metadata_results":metadata_records,
            "scalar_bridge_checks":scalar["checks"],
            "native_object_property_execution_verified":False,"populated_arrays_references_and_object_interchange_verified":False,
            "standard_object_handlers":"lifetime_method_lookup_subset_with_explicit_unsupported_guards_for_property_dimension_cast_and_enumeration",
            "diagnostic_comparison":"error class/message and error-handler-captured severity/message; not raw CLI stack/source-location formatting",
            "tracker_limit":"owned request allocations and controlled TLS lifecycle only; not a general leak/race proof",
            "PHP_FULL_COMPATIBLE":False,"linux_runtime_verified":False,"web_SAPI_verified":False}
    (out/"acceptance.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    manifest=[]
    files=list(out.glob("*.json"))+list(out.glob("*.log"))+list(out.glob("*.md"))+list((root/"native/php85abi/src").glob("*.cpp"))+list((root/"native/php85abi/include").glob("*.h"))+[root/"native/php85abi/Build-NativeAbi.ps1",root/"native/php85abi/README.md"]+list((root/"tools/abi").glob("*"))
    for p in sorted(set(files)):
        if p.is_file() and p.name!="SHA256SUMS.json":manifest.append({"path":p.relative_to(root).as_posix(),"sha256":digest(p),"size_bytes":p.stat().st_size})
    (out/"SHA256SUMS.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"status":report["status"],"unique_call_cases":len(unique_case_ids),"matched_comparisons":report["matched_call_comparisons"],"total_comparisons":len(comparisons),"checks_passed":sum(checks.values()),"checks_total":len(checks),"next_modules":[{k:r[k] for k in ["module","required_php_symbols"]}|{"missing_symbols":len(r["missing_symbol_names"])} for r in matrix if r["module"] in ["sqlite3","zend_test","FFI"]]},ensure_ascii=False))
    if not success:raise SystemExit(1)


if __name__=="__main__":main()
