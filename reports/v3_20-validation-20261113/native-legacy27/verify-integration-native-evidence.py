"""Read preserved native runs; verify evidence and index only owned reports."""
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
PACKAGE = ROOT / "package/ALL_PHP_v3_12_adapter.ps1"
EXPECTED = "5856687f7abd1471b4af7af9827ca2d17a011e836ad2852bf1d7993298fddc9f"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


assert digest(PACKAGE) == EXPECTED
for mode, folder, total, guards in (
    ("callback", "native-callback15", 15, 0),
    ("legacy", "native-legacy27", 23, 4),
):
    directory = HERE.parent / folder
    report_path = directory / "report.json"
    report = read(report_path)
    assert report["mode"] == mode
    assert report["passed"] == total == report["total_comparisons"]
    assert report["guard_cases"] == guards == report["guards_rejected_before_native"]
    assert report["inputs_unchanged"] is True
    assert report["inputs_before"] == report["inputs_after"]
    assert report["inputs_before"]["adapter"] == EXPECTED
    assert report["timeout_seconds"] == 30
    assert len(report["results"]) == total + guards
    checks = []
    for case in report["results"]:
        candidate, oracle, metadata = case["candidate"], case["oracle"], case["native_metadata"]
        assert case["inputs_stable_in_worker"] and case["own_native_core_verified"]
        assert candidate["state"] == oracle["state"] == "EXITED"
        assert digest(Path(case["source_path"])) == case["source_sha256"]
        assert metadata["inputs_before"] == metadata["inputs_after"]
        assert metadata["inputs_before"]["adapter"].lower() == EXPECTED
        assert metadata["inputs_before"]["source"].lower() == case["source_sha256"]
        assert metadata["inputs_before"]["core"].lower() == report["inputs_before"]["core"]
        loaded_cores = [Path(p).resolve() for p in metadata["loaded_php_modules"] if Path(p).name.lower() == "php8ts.dll"]
        assert loaded_cores == [Path(metadata["core_path"]).resolve()]
        assert digest(loaded_cores[0]) == report["inputs_before"]["core"]
        stats = metadata["native_stats"]
        assert stats["minit"] == stats["mshutdown"] == 1
        assert stats["rinit"] == stats["rshutdown"] == 1
        assert stats["tls_contexts_created"] == stats["tls_contexts_destroyed"] == 1
        assert stats["request_allocations_live"] == 0
        guard = case["native_guard_case"]
        if guard:
            assert case["verdict"] == "EXPECTED_ENGINE_REJECTION"
            assert candidate["exit_code"] == metadata["exit_code"] == 1
            assert metadata["native_unsupported"] is True
            assert stats["native_invocations"] == 0
        else:
            assert case["verdict"] == "PASS" and not case["differences"]
            for key in ("stdout_base64", "stderr_base64", "exit_code"):
                assert candidate[key] == oracle[key]
            assert candidate["exit_code"] == metadata["exit_code"]
        row = {
            "id": case["id"],
            "verdict": case["verdict"],
            "actual_exit_code": candidate["exit_code"],
            "native_invocations": stats["native_invocations"],
            "controlled_lifecycle_balanced": True,
            "guard_excluded_from_compatibility_count": bool(guard),
        }
        if mode == "callback":
            assert metadata["callback_stats"]["callback_owner_thread"] == 0
            row["callback_lease_released"] = True
        checks.append(row)
    if mode == "legacy":
        save(directory / "verification.json", {
            "status": "SELECTED_LEGACY_NATIVE_SOURCE_PROFILE_VERIFIED_NOT_FULL_PHP",
            "source_sha256": EXPECTED,
            "actual_package_path": PACKAGE.as_posix(),
            "passed": total,
            "total_comparisons": total,
            "guards_rejected_before_native": guards,
            "guards_excluded_from_compatibility_count": True,
            "same_source_raw_stdout_stderr_actual_status": True,
            "inputs_unchanged": True,
            "timeout_seconds": report["timeout_seconds"],
            "core_sha256": report["inputs_before"]["core"],
            "bridge_sha256": report["inputs_before"]["bridge"],
            "host_sha256": report["inputs_before"]["host"],
            "report_sha256": digest(report_path),
            "controlled_case_checks": checks,
            "limits": "Pinned Windows x64 TS dl_test scalar profile only. Normal outer-Main host. Controlled counters are not a general memory-safety proof. Original PS-worker failures remain preserved.",
        })
    else:
        verification = read(directory / "verification.json")
        assert verification["report_sha256"] == digest(report_path)
        assert verification["passed"] == verification["total"] == total
    files = [{"path": p.relative_to(directory).as_posix(), "bytes": p.stat().st_size, "sha256": digest(p)}
             for p in sorted(directory.rglob("*")) if p.is_file() and p.name != "artifact-manifest.json"]
    manifest_path = directory / "artifact-manifest.json"
    save(manifest_path, {"status": "FROZEN_SELECTED_NATIVE_EVIDENCE_NOT_FULL_PHP", "files": files})
    frozen = read(manifest_path)
    for item in frozen["files"]:
        p = directory / item["path"]
        assert p.stat().st_size == item["bytes"] and digest(p) == item["sha256"]
    print(json.dumps({"profile": mode, "comparisons": total, "guard_rejections": guards,
                      "manifest_entries": len(files), "manifest_sha256": digest(manifest_path)}))
