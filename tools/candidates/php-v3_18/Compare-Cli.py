"""Exact process comparison using the new CLI worker; original evaluator untouched."""
from pathlib import Path
import argparse
import importlib.util
import json
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
spec = importlib.util.spec_from_file_location("all_strict_compare", ROOT / "tools/differential/evaluate.py")
strict = importlib.util.module_from_spec(spec)
spec.loader.exec_module(strict)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cases", type=Path, default=ROOT / "tools/differential/cli-semantics.cases.json")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--adapter", type=Path, default=HERE / "ALL_PHP_v3_18_candidate.ps1")
    parser.add_argument("--php", type=Path, default=Path.home() / "ALL_php_oracle/php-8.5.12-ts-x64/php.exe")
    parser.add_argument("--powershell", type=Path, default=Path("C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"))
    parser.add_argument("--timeout", type=float, default=30)
    args = parser.parse_args()
    args.output = args.output.resolve()
    if args.output.exists():
        parser.error("Output exists; choose a new run directory to preserve evidence.")
    paths = {key: getattr(args, key).resolve(strict=True) for key in ["cases", "adapter", "php", "powershell"]}
    paths["worker"] = ROOT / "tools/differential/PhpCliCandidateWorker.ps1"
    paths["driver"] = Path(__file__).resolve()
    before = {key: strict.sha256(path) for key, path in paths.items()}
    cases = json.loads(paths["cases"].read_text(encoding="utf-8-sig"))
    if not cases or len({x["id"] for x in cases}) != len(cases):
        parser.error("Cases must be nonempty with unique IDs.")
    args.output.mkdir(parents=True)
    rows = []
    for index, case in enumerate(cases):
        source = args.output / f"case-{index:04d}.php"
        source.write_bytes(case["code"].encode("utf-8"))
        oracle = strict.run_process([str(paths["php"]), "-n", "-d", "display_errors=stderr", "-d", "error_reporting=-1", "-d", "date.timezone=UTC", str(source)], args.output, args.timeout)
        candidate = strict.run_process([str(paths["powershell"]), "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(paths["worker"]), "-AdapterPath", str(paths["adapter"]), "-SourcePath", str(source)], args.output, args.timeout)
        diff = strict.differences(oracle, candidate)
        rows.append({"id": case["id"], "source_path": str(source), "source_sha256": strict.sha256(source), "verdict": "PASS" if not diff else "DIFFERENT", "differences": diff, "oracle": oracle, "candidate": candidate})
        print(rows[-1]["verdict"] + ": " + case["id"], flush=True)
    after = {key: strict.sha256(path) for key, path in paths.items()}
    report = {"schema_version": 1, "status": "NOT_COMPLETE", "isolated_candidate": True,
              "driver_argv": [sys.executable, *sys.argv], "working_directory": str(Path.cwd()),
              "timeout_seconds": args.timeout,
              "measurement": "exact stdout bytes, stderr bytes and actual process status; no normalization",
              "scope": "Listed examples only; not full CLI/SAPI/PHP conformance.",
              "inputs_before": before, "inputs_after": after, "inputs_unchanged": before == after,
              "total": len(rows), "passed": sum(x["verdict"] == "PASS" for x in rows),
              "different": sum(x["verdict"] != "PASS" for x in rows), "results": rows}
    (args.output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: report[k] for k in ["passed", "total", "inputs_unchanged"]}))
    return 0 if report["passed"] == report["total"] and report["inputs_unchanged"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
