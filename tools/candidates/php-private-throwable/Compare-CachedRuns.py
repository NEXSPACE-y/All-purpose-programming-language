"""Compare cache-isolated Runs with identical sources in fresh official PHP processes."""
from pathlib import Path
import base64
import importlib.util
import json
import subprocess
import hashlib

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
spec = importlib.util.spec_from_file_location("private_strict", ROOT / "tools/differential/evaluate.py")
strict = importlib.util.module_from_spec(spec)
spec.loader.exec_module(strict)
output = ROOT / "reports/php-private-throwable-20261112/cached-runs-initial"
if output.exists():
    raise SystemExit("Output exists; preserve it and choose a new explicit run path.")
output.mkdir(parents=True)
base = ROOT / "tools/candidates/php-native/ALL_PHP_native_candidate.ps1"
candidate = HERE / "ALL_PHP_private_throwable_candidate.ps1"
worker = HERE / "Observe-CachedRuns.ps1"
php = Path.home() / "ALL_php_oracle/php-8.5.12-ts-x64/php.exe"
ps = Path("C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe")
paths = {"base": base, "candidate": candidate, "worker": worker, "php": php, "powershell": ps}
before = {k: strict.sha256(p) for k, p in paths.items()}
all_rows = []
for parity in [0, 1]:
    directory = output / f"parity-{parity}"
    directory.mkdir()
    seed = "<?php namespace A;" + ";" * parity + " define('A\\X',0);" + "X+X;" * 150 + " try {} catch(\\Throwable $e) {}"
    programs = [
        ("old-cache-warmup", "base", "<?php $e=new Exception('warm'); echo $e->__toString();"),
        ("private-cold-namespace", "private", seed),
        ("cached-user-hijack", "private", "<?php function __all_throwable_string($e){return 'hijacked';} $e=new Exception('x'); echo $e->__toString();"),
        ("ordinary-user-call", "private", "<?php function __all_throwable_string($x){return 'user';} echo __all_throwable_string(1);"),
        ("later-clean-run", "private", "<?php var_dump(function_exists('__all_throwable_string')); $e=new Exception('later'); echo $e->__toString();")]
    sequence = []
    oracles = {}
    for i, (id, adapter, code) in enumerate(programs):
        source = directory / f"case-{i:02d}.php"
        source.write_bytes(code.encode("utf-8"))
        sequence.append({"id": id, "adapter": adapter, "source_path": str(source)})
        oracles[id] = strict.run_process([str(php), "-n", "-d", "display_errors=stderr", "-d", "error_reporting=-1", "-d", "date.timezone=UTC", str(source)], directory, 60)
    seq = directory / "sequence.json"
    seq.write_text(json.dumps(sequence, indent=2) + "\n", encoding="utf-8")
    observed = directory / "observed.json"
    argv = [str(ps), "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(worker), "-BaseAdapterPath", str(base), "-AdapterPath", str(candidate), "-SequencePath", str(seq), "-ReportPath", str(observed)]
    process = strict.run_process(argv, directory, 180)
    (directory / "worker-process.json").write_text(json.dumps(process, indent=2) + "\n", encoding="utf-8")
    if process["state"] != "EXITED" or process["exit_code"] != 0 or not observed.is_file():
        raise RuntimeError(process)
    data = json.loads(observed.read_text(encoding="utf-8-sig"))
    assert not data["cache_reset_performed"]
    for row in data["results"]:
        oracle = oracles[row["id"]]
        differences = []
        if row["stdout"].encode("utf-8") != base64.b64decode(oracle["stdout_base64"]): differences.append("stdout")
        if row["stderr"].encode("utf-8") != base64.b64decode(oracle["stderr_base64"]): differences.append("stderr")
        if row["error"] is not None or row["pipeline_count"] != 0: differences.append("host_error_or_pipeline")
        if row["context_exit_code"] != oracle["exit_code"]: differences.append("context_status_vs_oracle_process_status")
        result = {"parity": parity, "source_sha256": strict.sha256(Path(row["source_path"])), "candidate_run": row, "oracle": oracle, "differences": differences, "matched": not differences, "host_process_id": data["process_id"]}
        all_rows.append(result)
        print(json.dumps({"parity": parity, "id": row["id"], "matched": not differences, "differences": differences}), flush=True)
after = {k: strict.sha256(p) for k, p in paths.items()}
report = {"status": "NOT_COMPLETE", "scope": "Same-process cache isolation; captured Console text encoded UTF8 compared with independent official-process bytes. Context status is not claimed as a separate candidate process exit.", "inputs_before": before, "inputs_after": after, "inputs_unchanged": before == after, "cache_reset_performed": False, "total": len(all_rows), "matched": sum(r["matched"] for r in all_rows), "private_runs": sum(r["candidate_run"]["adapter"] == "private" for r in all_rows), "results": all_rows}
(output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({k: report[k] for k in ["total", "matched", "private_runs", "inputs_unchanged"]}))
