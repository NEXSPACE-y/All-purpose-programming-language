"""Read terminal integration reports; preserve differences and actual statuses."""
from pathlib import Path
import base64
import hashlib
import json

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
ADAPTER = "4d120c8ff1e6f2179e2dee5cd2ef4726d2ff05d168fac536f34721c8c9e13a9c"
RUNTIME = "18d50efb55d8a333424149e4ab37428e102b1ac938240e50358ee3c8ab89466b"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def main():
    profiles = []
    for suffix, comparisons, guards in (("legacy27",23,4),("callback15",15,0),("raw4",4,0)):
        directory = HERE.parent / ("native-integration-combined03-" + suffix)
        report = read(directory / "report.json")
        assert report["total_comparisons"] == comparisons and report["guard_cases"] == guards
        assert report["passed"] == comparisons and report["guards_rejected_before_native"] == guards
        assert report["timeout_seconds"] == 30
        assert report["inputs_before"]["adapter"] == ADAPTER
        assert report["inputs_before"]["runtime"] == RUNTIME
        assert report["inputs_before"] == report["inputs_after"] and report["inputs_unchanged"]
        for name, path in report["input_paths"].items():
            assert digest(Path(path)) == report["inputs_before"][name]
        lifecycle = []
        for case in report["results"]:
            native = case["native_metadata"]
            actual = case["candidate"]
            assert actual["state"] == "EXITED"
            assert native and native["inputs_before"] == native["inputs_after"]
            assert actual["exit_code"] == native["exit_code"]
            assert case["inputs_stable_in_worker"] and case["own_native_core_verified"] and case["canonical_runtime_location_verified"]
            assert digest(Path(case["source_path"])) == case["source_sha256"]
            stats = native["native_stats"]
            balanced = stats["minit"] == stats["mshutdown"] == stats["rinit"] == stats["rshutdown"] == stats["tls_contexts_created"] == stats["tls_contexts_destroyed"] == 1 and stats["request_allocations_live"] == 0
            assert balanced
            if report["mode"] == "callback":
                assert native["callback_stats"]["callback_owner_thread"] == 0
            if case["native_guard_case"]:
                assert case["verdict"] == "EXPECTED_ENGINE_REJECTION" and actual["exit_code"] == 1 and stats["native_invocations"] == 0
            elif case["verdict"] == "PASS":
                for key in ("stdout_base64", "stderr_base64", "exit_code"):
                    assert actual[key] == case["oracle"][key]
            row = {"id":case["id"],"verdict":case["verdict"],"actual_exit_code":actual["exit_code"],"native_invocations":stats["native_invocations"],"controlled_lifecycle_balanced":balanced}
            if suffix == "raw4":
                assert stats["native_invocations"] == 1
                data = base64.b64decode(actual["stdout_base64"])
                row["raw_stdout_sha256"] = hashlib.sha256(data).hexdigest()
                row["raw_stdout_bytes"] = len(data)
            lifecycle.append(row)
        profile = {"profile":suffix,"passed":report["passed"],"total_comparisons":comparisons,"guards_rejected_before_native":report["guards_rejected_before_native"],"guards_separate":guards,"inputs_unchanged":True,"report_sha256":digest(directory/"report.json"),"cases":lifecycle}
        (directory / "verification.json").write_text(json.dumps(profile,indent=2)+"\n",encoding="utf-8")
        profiles.append(profile)
    summary = {"status":"SELECTED_NATIVE_BYTE_SOURCE_INTEGRATION_NOT_FULL_PHP","adapter_sha256":ADAPTER,"runtime_sha256":RUNTIME,"profiles":profiles,"module_info_component_failures_unmodified":2,"stock_php_execution_delegation":False}
    (HERE / "summary.json").write_text(json.dumps(summary,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"profiles":[{k:p[k]for k in ("profile","passed","total_comparisons","guards_rejected_before_native")}for p in profiles]}))


if __name__ == "__main__":
    main()
