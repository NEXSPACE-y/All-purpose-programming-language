"""Frozen same-source evaluator fixtures on a separate byte native host profile.

No execution occurs on import. Root explicitly authorizes each serialized run.
Original legacy/callback fixtures and their 30s timeout remain unchanged.
"""
from pathlib import Path
import argparse
import importlib.util
import json
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
spec = importlib.util.spec_from_file_location("strict", ROOT / "tools/differential/evaluate.py")
strict = importlib.util.module_from_spec(spec)
spec.loader.exec_module(strict)
RUNTIME = ROOT / "tools/candidates/php-byte-runtime/out/runtime01/AllPhp.ByteValues.Runtime.dll"
BRIDGE = ROOT / "tools/candidates/php-byte-native/out/build05/AllPhp.NativeBytes.Bridges.dll"
RUNTIME_HASH = "18d50efb55d8a333424149e4ab37428e102b1ac938240e50358ee3c8ab89466b"
BRIDGE_HASH = "4bdbb60db0da70140224dac092507aa8d911f7d86738680b53172c979f712932"
CASES = {
    "callback": (ROOT / "tools/candidates/php-native-callback/callback-source.cases.json", "c2ac4a4f5777648389c81b5aacb2dfc64c04e4e43190ca36379970a8b83cf0fd"),
    "legacy": (ROOT / "tools/candidates/php-native/native-source.cases.json", "bb0f0ce864c0b2ec415e1df3d836eb65fe2f16a55387dadf1ecf2440f81ab155"),
}
CORE = {
    "callback": (ROOT / "native/php85abi-callback/out/windows-x64-ts/php8ts.dll", "88117b8f38dc77d20e638ce573bb83fc6f959c1ad6821f8803c5499969fe234b"),
    "legacy": (ROOT / "native/php85abi/out/windows-x64-ts/php8ts.dll", "b2ffd9f38abd20894b064b53a94e4a05e5d39eaa2055e910db6d762558e46757"),
}


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", choices=["callback", "legacy", "raw"], required=True)
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--adapter", type=Path, required=True)
    parser.add_argument("--expected-adapter-sha256", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--timeout", type=float, default=30)
    args = parser.parse_args()
    if args.timeout != 30:
        parser.error("This profile preserves the original 30-second timeout")
    output = args.output.resolve()
    if output.exists():
        parser.error("Preserve prior runs; use a fresh output directory")
    mode = "legacy" if args.suite == "legacy" else "callback"
    case_path = HERE / "raw-source.cases.json" if args.suite == "raw" else CASES[args.suite][0]
    paths = {
        "host": args.host.resolve(strict=True), "adapter": args.adapter.resolve(strict=True),
        "cases": case_path.resolve(strict=True), "runtime": RUNTIME, "bridge": BRIDGE,
        "core": CORE[mode][0], "extension": Path("C:/Users/rinpa/ALL_php_oracle/php-8.5.12-ts-x64/ext/php_dl_test.dll"),
        "php": Path("C:/Users/rinpa/ALL_php_oracle/php-8.5.12-ts-x64/php.exe"),
        "driver": Path(__file__).resolve(), "helper": ROOT / "tools/differential/evaluate.py",
        "worker": args.host.resolve().parent / "byte-return-worker.ps1", "host_build": args.host.resolve().parent / "build.json",
    }
    before = {key: strict.sha256(path) for key, path in paths.items()}
    expected = {"runtime": RUNTIME_HASH, "bridge": BRIDGE_HASH, "adapter": args.expected_adapter_sha256, "core": CORE[mode][1],
                "extension": "532b9f0944d482a704eb81ac1cb9af3b59aa0f54c753c53a5709c17f57d4e938",
                "php": "0ac893499799256db6d3a54b0da73692e02311493922e6e4f86a062674a77d66"}
    if args.suite != "raw":
        expected["cases"] = CASES[args.suite][1]
    for key, pin in expected.items():
        if before[key] != pin:
            parser.error("Selected input hash mismatch: " + key)
    build = json.loads(paths["host_build"].read_text(encoding="utf-8-sig"))
    if build["inputs_before"] != build["inputs_after"]:
        parser.error("Host build inputs changed during compilation")
    for label, path in build["input_paths"].items():
        if strict.sha256(Path(path)) != build["inputs_before"][label]:
            parser.error("Host source changed since build: " + label)
    for item in build["files"]:
        if strict.sha256(paths["host"].parent / item["path"]) != item["sha256"]:
            parser.error("Host build output changed: " + item["path"])
    cases = json.loads(paths["cases"].read_text(encoding="utf-8-sig"))
    if not cases or len({case["id"] for case in cases}) != len(cases):
        parser.error("Need nonempty unique fixture IDs")
    output.mkdir(parents=True)
    rows = []
    for index, case in enumerate(cases):
        source = output / ("case-" + str(index).zfill(4) + ".php")
        source.write_bytes(case["code"].encode("utf-8"))
        metadata = output / ("case-" + str(index).zfill(4) + ".native.json")
        reference = strict.run_process([str(paths["php"]), "-n", "-d", "extension=" + str(paths["extension"]), "-d", "display_errors=stderr", "-d", "error_reporting=-1", "-d", "date.timezone=UTC", str(source)], output, args.timeout)
        candidate = strict.run_process([str(paths["host"]), mode, str(paths["adapter"]), str(source), str(paths["core"]), str(paths["extension"]), str(metadata), before["core"], str(paths["runtime"]), str(paths["bridge"]), before["runtime"], before["bridge"], before["adapter"]], output, args.timeout)
        meta = json.loads(metadata.read_text(encoding="utf-8-sig")) if metadata.exists() else None
        diff = strict.differences(reference, candidate)
        stable = bool(meta) and meta.get("inputs_before") == meta.get("inputs_after")
        modules = meta.get("loaded_php_modules", []) if meta else []
        if isinstance(modules, str):
            modules = [modules]
        selected = [m for m in modules if Path(m).name.lower() == "php8ts.dll"]
        own_core = len(selected) == 1 and selected[0].lower() == str(paths["core"]).lower()
        canonical = bool(meta) and meta.get("runtime_assembly_location", "").lower() == str(RUNTIME).lower()
        guard = case.get("expect_native_guard", False)
        if guard:
            good = candidate["state"] == "EXITED" and candidate["exit_code"] == 1 and bool(meta) and meta.get("native_unsupported") and meta.get("native_stats", {}).get("native_invocations") == 0
            verdict = "EXPECTED_ENGINE_REJECTION" if good and stable and own_core and canonical else "GUARD_FAILURE"
        else:
            verdict = "PASS" if not diff and stable and own_core and canonical and meta.get("native_context_parameter_verified") else "DIFFERENT"
        rows.append({"id": case["id"], "source_path": str(source), "source_sha256": strict.sha256(source), "verdict": verdict,
                     "native_guard_case": guard, "differences": diff, "inputs_stable_in_worker": stable,
                     "own_native_core_verified": own_core, "canonical_runtime_location_verified": canonical,
                     "oracle": reference, "candidate": candidate, "native_metadata": meta})
        print(verdict + ": " + case["id"], flush=True)
        save(output / "report.partial.json", {"status": "IN_PROGRESS", "results": rows})
    after = {key: strict.sha256(path) for key, path in paths.items()}
    normal = [row for row in rows if not row["native_guard_case"]]
    guards = [row for row in rows if row["native_guard_case"]]
    report = {"status": "SELECTED_BYTE_NATIVE_SOURCE_INTEGRATION_NOT_FULL_PHP", "measurement": "Same PHP source, exact raw stdout/stderr and actual process status; no normalization",
              "suite": args.suite, "mode": mode, "host_profile": "Normal outer Main after runspace disposal; canonical original runtime preloaded before bridge",
              "timeout_seconds": args.timeout, "driver_argv": [sys.executable, *sys.argv], "input_paths": {key: str(path) for key, path in paths.items()},
              "inputs_before": before, "inputs_after": after, "inputs_unchanged": before == after,
              "total_comparisons": len(normal), "passed": sum(row["verdict"] == "PASS" for row in normal), "guard_cases": len(guards),
              "guards_rejected_before_native": sum(row["verdict"] == "EXPECTED_ENGINE_REJECTION" for row in guards), "results": rows}
    save(output / "report.json", report)
    print(json.dumps({key: report[key] for key in ("passed", "total_comparisons", "guard_cases", "guards_rejected_before_native", "inputs_unchanged")}))
    return 0 if report["passed"] == len(normal) and report["guards_rejected_before_native"] == len(guards) and before == after else 1


if __name__ == "__main__":
    raise SystemExit(main())
