"""Replay original cached10 sources against an explicitly selected actual package.

The original candidate, fixtures, sources, and reports are read only. Per-Run
Console text is compared as UTF8 with fresh official PHP-process output; the
candidate context status is identified separately from the observer process.
"""
from pathlib import Path
import argparse
import base64
import importlib.util
import json

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--package", type=Path, required=True)
parser.add_argument("--expected-sha256", required=True)
args = parser.parse_args()
if not args.package.is_absolute():
    parser.error("Specify the actual package with an absolute path.")
package = args.package.resolve(strict=True)
spec = importlib.util.spec_from_file_location("v319_cache_strict", ROOT / "tools/differential/evaluate.py")
strict = importlib.util.module_from_spec(spec)
spec.loader.exec_module(strict)
if strict.sha256(package) != args.expected_sha256:
    parser.error("Actual package hash differs from the requested frozen version.")
output = Path(__file__).resolve().parent / "run-01"
if output.exists():
    parser.error("Output exists; never overwrite prior evidence.")
output.mkdir()
base = ROOT / "tools/candidates/php-native/ALL_PHP_native_candidate.ps1"
worker = ROOT / "tools/candidates/php-private-throwable/Observe-CachedRuns.ps1"
original = ROOT / "reports/php-private-throwable-20261112/cached-runs-initial"
original_report = json.loads((original / "report.json").read_text(encoding="utf-8"))
php = Path.home() / "ALL_php_oracle/php-8.5.12-ts-x64/php.exe"
ps = Path("C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe")
paths = {"actual_package": package, "base_cache_warmup_adapter": base,
         "worker": worker, "oracle_php": php, "powershell": ps,
         "original_report": original / "report.json", "driver": Path(__file__).resolve()}
before = {k: strict.sha256(p) for k, p in paths.items()}
(output / "actual-package.snapshot.ps1").write_bytes(package.read_bytes())
(output / "worker.snapshot.ps1").write_bytes(worker.read_bytes())
all_rows = []
host_processes = []
source_hashes = {}
for parity in [0, 1]:
    directory = output / f"parity-{parity}"
    directory.mkdir()
    original_sequence = json.loads((original / f"parity-{parity}/sequence.json").read_text(encoding="utf-8"))
    sequence = []
    oracles = {}
    for index, step in enumerate(original_sequence):
        old_source = Path(step["source_path"])
        raw = old_source.read_bytes()
        old_record = next(r for r in original_report["results"] if r["parity"] == parity and r["candidate_run"]["id"] == step["id"])
        if strict.sha256(old_source) != old_record["source_sha256"]:
            raise RuntimeError("An original cached-run source changed.")
        source_hashes[str(old_source)] = strict.sha256(old_source)
        source = directory / f"case-{index:02d}.php"
        source.write_bytes(raw)
        if strict.sha256(source) != old_record["source_sha256"]:
            raise RuntimeError("Source bytes were not replayed exactly.")
        sequence.append({"id": step["id"], "adapter": step["adapter"], "source_path": str(source)})
        oracles[step["id"]] = strict.run_process([str(php), "-n", "-d", "display_errors=stderr", "-d", "error_reporting=-1", "-d", "date.timezone=UTC", str(source)], directory, 60)
    seq = directory / "sequence.json"
    seq.write_text(json.dumps(sequence, indent=2) + "\n", encoding="utf-8")
    observed = directory / "observed.json"
    command = [str(ps), "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(worker), "-BaseAdapterPath", str(base), "-AdapterPath", str(package), "-SequencePath", str(seq), "-ReportPath", str(observed)]
    host = strict.run_process(command, directory, 180)
    host_processes.append(host)
    (directory / "worker-process.json").write_text(json.dumps(host, indent=2) + "\n", encoding="utf-8")
    if host["state"] != "EXITED" or host["exit_code"] != 0 or not observed.is_file():
        raise RuntimeError(host)
    data = json.loads(observed.read_text(encoding="utf-8-sig"))
    if data["cache_reset_performed"] or data["adapter_sha256_before"].lower() != args.expected_sha256 or data["adapter_sha256_after"].lower() != args.expected_sha256:
        raise RuntimeError("Observer cache/hash invariant failed.")
    for row in data["results"]:
        oracle = oracles[row["id"]]
        diff = []
        if row["stdout"].encode("utf-8") != base64.b64decode(oracle["stdout_base64"]): diff.append("stdout")
        if row["stderr"].encode("utf-8") != base64.b64decode(oracle["stderr_base64"]): diff.append("stderr")
        if row["error"] is not None or row["pipeline_count"] != 0: diff.append("host_error_or_pipeline")
        if oracle["state"] != "EXITED" or row["context_exit_code"] != oracle["exit_code"]: diff.append("context_status_vs_oracle_process_status")
        all_rows.append({"parity": parity, "actual_adapter_path": str(base if row["adapter"] == "base" else package),
                         "role": "base_cache_warmup" if row["adapter"] == "base" else "actual_package_run",
                         "original_source_bytes_preserved": True, "source_sha256": strict.sha256(Path(row["source_path"])),
                         "candidate_run": row, "oracle": oracle, "differences": diff, "matched": not diff,
                         "observer_process_id": data["process_id"]})
        print(json.dumps({"parity": parity, "id": row["id"], "matched": not diff, "differences": diff}), flush=True)
after = {k: strict.sha256(p) for k, p in paths.items()}
sources_unchanged = all(strict.sha256(Path(p)) == digest for p, digest in source_hashes.items())
report = {"status": "NOT_COMPLETE", "scope": "Original cached10 replay:2old-adapter warmups+8actual-package Runs. Captured Console text encodedUTF8 compared with independent official-process bytes; per-Run context status is not labelled a candidate process exit.",
          "actual_package_path": str(package), "actual_package_sha256": args.expected_sha256,
          "inputs_before": before, "inputs_after": after, "inputs_unchanged": before == after,
          "original_sources_unchanged": sources_unchanged, "cache_reset_performed": False,
          "total": len(all_rows), "matched": sum(r["matched"] for r in all_rows),
          "actual_package_runs": sum(r["role"] == "actual_package_run" for r in all_rows),
          "host_processes": host_processes, "results": all_rows}
(output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({k: report[k] for k in ["total", "matched", "actual_package_runs", "inputs_unchanged", "original_sources_unchanged"]}))
if report["matched"] != report["total"] or before != after or not sources_unchanged:
    raise SystemExit(1)
