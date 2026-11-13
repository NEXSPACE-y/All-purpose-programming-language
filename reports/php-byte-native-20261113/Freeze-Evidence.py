"""Verify preserved byte bridge evidence and freeze this task's owned files."""
import base64
import difflib
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
CANDIDATE = ROOT / "tools/candidates/php-byte-native"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


first, current = [read(HERE / name / "report.json") for name in ("run01", "run02")]
assert first["passed"] == 0 and first["failed"] == 40 and first["inputs_unchanged"]
assert current["passed"] == 34 and current["guard_rejections"] == 4 and current["failed"] == 2
assert current["inputs_unchanged"]
assert len(first["results"]) == len(current["results"]) == 40
assert read(HERE / "run01/fixtures.json") == read(HERE / "run02/fixtures.json")
for report in (first, current):
    assert report["timeout_seconds"] == 30 and report["native_function_retries"] == 0
    assert report["inputs_before"] == report["inputs_after"]
    for path, expected in report["inputs_before"].items():
        assert digest(Path(path)) == expected, path
for case in first["results"]:
    metadata = case["native_metadata"]
    assert metadata["managed_exception"] == "System.InvalidCastException"
    assert metadata["stats_after_call"]["native_invocations"] == 0
    assert case["candidate"]["state"] == "EXITED" and case["candidate"]["actual_status"] == 0
differences = []
for case in current["results"]:
    assert case["candidate"]["state"] == "EXITED" and case["candidate"]["actual_status"] == 0
    metadata = case["native_metadata"]
    assert metadata["stats_final"]["request_allocations_live"] == 0
    if case["verdict"] == "FAIL":
        assert case["id"].endswith("raw_ini_module_output") and case["differences"] == ["raw stdout/stderr bytes differ"]
        actual = base64.b64decode(case["candidate"]["stdout_base64"])
        expected = base64.b64decode(case["oracle"]["stdout_base64"])
        payload = bytes(range(1, 256))
        assert payload in actual and payload in expected
        operations = [{"operation": op, "own_range": [a,b], "php_range": [c,d],
                       "own_bytes_base64": base64.b64encode(actual[a:b]).decode("ascii"),
                       "php_bytes_base64": base64.b64encode(expected[c:d]).decode("ascii")}
                      for op,a,b,c,d in difflib.SequenceMatcher(None,actual,expected,autojunk=False).get_opcodes() if op != "equal"]
        assert len(operations) == 2 and all(item["operation"] == "insert" for item in operations)
        differences.append({"id": case["id"], "compatibility_verdict": "FAIL", "own_stdout_bytes": len(actual),
                            "php_stdout_bytes": len(expected), "all_nonzero_255_payload_preserved_in_both": True,
                            "native_ini_bytes_equal_reference": metadata["ini_value_base64"] == case["oracle_metadata"]["ini_value_base64"],
                            "raw_difference_operations": operations})
    elif case["verdict"] == "PASS":
        assert not case["differences"]
        for key in ("stdout_base64", "stderr_base64", "actual_status"):
            assert case["candidate"][key] == case["oracle"][key]
    else:
        assert case["verdict"] == "EXPECTED_MANAGED_BOUNDARY_REJECTION"
        assert metadata["stats_after_call"]["native_invocations"] == metadata["stats_before"]["native_invocations"] == 0
contract = read(HERE / "callback-contract01/process.json")
assert contract["pass"] and contract["actual_status"] == 0 and contract["state"] == "EXITED" and contract["inputs_unchanged"]
assert contract["contract"]["passed_checks"] == 12
for path, expected in contract["inputs_before"].items():
    assert digest(Path(path)) == expected
save(HERE / "module-info-differences.json", {"status": "TWO_UNNORMALIZED_OUTPUT_DIFFERENCES_REMAIN", "results": differences})
build = CANDIDATE / "out/build05/build.json"
(HERE / "build05").mkdir(exist_ok=True)
(HERE / "build05/build.json").write_bytes(build.read_bytes())
assessment = {
    "status": "BYTE_NATIVE_COMPONENT_IMPLEMENTED_SELECTED_COMPARISONS_PASS_TWO_MODULE_INFO_DIFFERENCES_REMAIN",
    "PHP_FULL_COMPATIBLE": False, "package_adopted": False,
    "candidate_sources": str(CANDIDATE / "generated04"),
    "build": str(CANDIDATE / "out/build05"), "build_record_sha256": digest(build),
    "canonical_byte_runtime_sha256": "18d50efb55d8a333424149e4ab37428e102b1ac938240e50358ee3c8ab89466b",
    "comparisons_passed": 34, "managed_guards_separate": 4, "module_info_differences_failed": 2,
    "controlled_contract_checks_separate": 12, "same_fixture_bytes_between_runs": True,
    "first_run": "40 probe fixture ArrayList cast failures before any own extension function; retained unchanged",
    "second_run": "Only probe ArrayList handling revised; bridge source, fixtures, values, core, extension and timeout unchanged",
    "frozen_package_sha256": "5856687f7abd1471b4af7af9827ca2d17a011e836ad2852bf1d7993298fddc9f",
    "native_cpp_or_dll_changed": False, "old_37_and_75_fixtures_unchanged_not_replaced": True,
    "old_fixtures_rerun_by_this_task": False,
    "limits": ["Pinned Windows x64 TS C dl_test; no Linux/Web/arbitrary native ABI proof",
               "Native identifiers retain existing strict UTF8 C-string API; raw byte names deferred",
               "Existing error_message/INI exports lack lengths and cannot expose embedded-NUL suffixes",
               "Original PS-worker timeout/CLR failures remain separate",
               "Controlled synthetic all-byte diagnostic transport is not a real dl_test diagnostic or compatibility case",
               "Module info reference has additional module and INI table headings; exact output comparison remains failed"],
}
save(HERE / "assessment.json", assessment)
files = []
for directory in (CANDIDATE, HERE):
    for path in sorted(directory.rglob("*")):
        if path.is_file() and path != HERE / "artifact-manifest.json":
            files.append({"path": path.relative_to(ROOT).as_posix(), "bytes": path.stat().st_size, "sha256": digest(path)})
save(HERE / "artifact-manifest.json", {"status": "FROZEN_BYTE_NATIVE_EVIDENCE_NOT_FULL_PHP", "files": files})
for item in files:
    assert digest(ROOT / item["path"]) == item["sha256"]
print(json.dumps({"comparisons_passed": 34, "guards": 4, "module_info_failures": 2, "controlled_checks": 12,
                  "manifest_entries": len(files), "manifest_sha256": digest(HERE / "artifact-manifest.json")}))
