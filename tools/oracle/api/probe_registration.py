"""Observe function_exists for every internal name in an actual oracle profile.

The generated PHP calls ONLY function_exists and echo. It never invokes the
reflected functions. Registration observations are not implementation proofs.
Python standard library only; no runtime/profile/fixture files are modified.
"""
from __future__ import annotations

import argparse
import base64
from collections import Counter
import datetime
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import secrets
import sys

ROOT = Path(__file__).resolve().parents[3]
COMPARE_PATH = ROOT / "tools/differential/evaluate.py"
spec = importlib.util.spec_from_file_location("registration_strict_compare", COMPARE_PATH)
strict = importlib.util.module_from_spec(spec)
spec.loader.exec_module(strict)


def php_literal(raw: bytes) -> bytes:
    return b"'" + raw.replace(b"\\", b"\\\\").replace(b"'", b"\\'") + b"'"


def program(rows: list[dict]) -> bytes:
    lines = [b"<?php\n"]
    for row in rows:
        index = (f"{row['index']:06d}:").encode("ascii")
        name = base64.b64decode(row["name_base64"], validate=True)
        lines.append(b"echo '" + index + b"', function_exists(" + php_literal(name) + b") ? '1' : '0', \"\\n\";\n")
    return b"".join(lines)


def parse_observations(process: dict, expected_indices: list[int]) -> tuple[dict[int, bool], str | None]:
    if process["state"] != "EXITED" or process["exit_code"] != 0:
        return {}, "Process did not exit successfully; no missing observation is inferred false."
    raw = base64.b64decode(process["stdout_base64"], validate=True)
    values = {}
    end = 0
    seen = []
    for match in re.finditer(rb"([0-9]{6}):([01])\n", raw):
        if match.start() != end:
            return {}, "Unexpected raw output bytes; no whitespace/newline normalization performed."
        index = int(match.group(1))
        if index in values:
            return {}, "Duplicate observation index."
        values[index] = match.group(2) == b"1"
        seen.append(index)
        end = match.end()
    if end != len(raw) or seen != expected_indices:
        return {}, "Missing/reordered/extra observation or unexpected trailing bytes."
    return values, None


def save_raw(directory: Path, name: str, process: dict) -> None:
    for stream in ["stdout", "stderr"]:
        (directory / f"{name}.{stream}.bin").write_bytes(base64.b64decode(process[f"{stream}_base64"]))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory", type=Path, default=ROOT / "reports/php-api-inventory-20261112/run-01")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--adapter", type=Path, default=ROOT / "package/ALL_PHP_v3_12_adapter.ps1")
    parser.add_argument("--php", type=Path, default=Path.home() / "ALL_php_oracle/php-8.5.12-ts-x64/php.exe")
    parser.add_argument("--powershell", type=Path, default=Path("C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"))
    parser.add_argument("--max-source-chars", type=int, default=100000)
    parser.add_argument("--names-per-process", type=int, default=100)
    parser.add_argument("--timeout", type=float, default=120)
    parser.add_argument("--sentinel", default=None)
    args = parser.parse_args()
    if not 1 <= args.max_source_chars <= 100000 or args.names_per_process < 1 or args.timeout <= 0:
        parser.error("Invalid source/process limit.")
    output = args.output.resolve()
    if output.exists():
        parser.error("Output already exists; use a new directory and preserve earlier observations.")
    inventory = args.inventory.resolve(strict=True)
    summary_path = inventory / "summary.json"
    profile_path = inventory / "profiles/base/stdout.json"
    summary = json.loads(summary_path.read_text(encoding="utf-8-sig"))
    profile = json.loads(profile_path.read_text(encoding="utf-8-sig"))
    if profile.get("mode") != "OFFICIAL_ORACLE_REFLECTION_ONLY" or profile["target"]["php_version"] != "8.5.12":
        parser.error("Expected the actual PHP8.5.12 official base profile.")
    functions = profile["functions"]
    if len(functions) != summary["base_counts"]["function"] or not all(f["internal"] for f in functions):
        parser.error("Base internal-function profile/summary mismatch; no filtering or replacement allowed.")
    rows = []
    for index, function in enumerate(functions):
        raw = base64.b64decode(function["name_base64"], validate=True)
        if raw.decode("utf-8") != function["name"]:
            parser.error("Name text/base64 mismatch; no lossy substitution allowed.")
        rows.append({"index": index, "name": function["name"], "name_base64": function["name_base64"],
                     "origin": "base_internal_registration", "extension": function.get("extension")})
    sentinel = args.sentinel or ("__all_unregistered_probe_" + secrets.token_hex(16))
    if not re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*", sentinel):
        parser.error("Sentinel must be an ordinary PHP identifier literal.")
    for label, name in [("internal_helper_extra", "__all_throwable_string"), ("unregistered_random_literal", sentinel)]:
        rows.append({"index": len(rows), "name": name, "name_base64": base64.b64encode(name.encode()).decode(), "origin": label, "extension": None})
    if len({r["name_base64"] for r in rows}) != len(rows):
        parser.error("Duplicate input name, including extras; do not silently drop any entry.")
    paths = {"summary": summary_path, "base_profile": profile_path,
             "adapter": args.adapter.resolve(strict=True), "php": args.php.resolve(strict=True),
             "powershell": args.powershell.resolve(strict=True),
             "worker": ROOT / "tools/differential/PhpCliCandidateWorker.ps1",
             "script": Path(__file__).resolve(), "comparator": COMPARE_PATH}
    before = {key: strict.sha256(path) for key, path in paths.items()}
    if before["php"] != summary["fixed_oracle_sha256"]:
        parser.error("Official binary hash differs from actual reflected profile.")
    chunks = []
    current = []
    for row in rows:
        proposed = current + [row]
        raw = program(proposed)
        # Byte limit is conservative for UTF-8 source; both byte and char counts
        # are recorded. No input name is dropped to meet the cap.
        if current and (len(proposed) > args.names_per_process or len(raw) > args.max_source_chars):
            chunks.append(current)
            current = [row]
        else:
            current = proposed
        if len(program(current)) > args.max_source_chars:
            parser.error("A single name cannot fit the requested source limit.")
    if current:
        chunks.append(current)
    output.mkdir(parents=True)
    (output / "names.json").write_text(json.dumps(rows, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (output / "adapter.snapshot.ps1").write_bytes(paths["adapter"].read_bytes())
    (output / "worker.snapshot.ps1").write_bytes(paths["worker"].read_bytes())
    processes = []
    observations = []
    operational_errors = []
    for chunk_index, names in enumerate(chunks):
        if strict.sha256(paths["adapter"]) != before["adapter"]:
            operational_errors.append("Adapter changed during run; remaining names unobserved.")
            break
        directory = output / f"chunk-{chunk_index:03d}"
        directory.mkdir()
        code = program(names)
        source = directory / "probe.php"
        source.write_bytes(code)
        oracle = strict.run_process([str(paths["php"]), "-n", "-d", "display_errors=stderr", "-d", "error_reporting=-1", "-d", "date.timezone=UTC", str(source)], directory, args.timeout)
        candidate = strict.run_process([str(paths["powershell"]), "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(paths["worker"]), "-AdapterPath", str(paths["adapter"]), "-SourcePath", str(source)], directory, args.timeout)
        save_raw(directory, "oracle", oracle)
        save_raw(directory, "candidate", candidate)
        indices = [r["index"] for r in names]
        oracle_values, oracle_error = parse_observations(oracle, indices)
        candidate_values, candidate_error = parse_observations(candidate, indices)
        differences = strict.differences(oracle, candidate)
        entry = {"chunk": chunk_index, "name_count": len(names), "indices": indices,
                 "source_path": str(source), "source_sha256": strict.sha256(source),
                 "source_bytes": len(code), "source_chars": len(code.decode("utf-8")),
                 "strict_differences": differences, "oracle_parse_error": oracle_error,
                 "candidate_parse_error": candidate_error, "oracle": oracle, "candidate": candidate}
        (directory / "processes.json").write_text(json.dumps(entry, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        processes.append(entry)
        for row in names:
            index = row["index"]
            a, b = oracle_values.get(index), candidate_values.get(index)
            observations.append({**row, "chunk": chunk_index, "source_sha256": entry["source_sha256"],
                                 "oracle_registered": a, "candidate_registered": b,
                                 "both_observed": a is not None and b is not None,
                                 "registration_matches": a == b if a is not None and b is not None else None})
        if oracle_error or candidate_error:
            operational_errors.append({"chunk": chunk_index, "oracle": oracle_error, "candidate": candidate_error})
        print(json.dumps({"chunk": chunk_index, "names": len(names), "source_chars": entry["source_chars"], "oracle_rows": len(oracle_values), "candidate_rows": len(candidate_values), "strict_differences": differences}), flush=True)
    observed_indices = {r["index"] for r in observations}
    for row in rows:
        if row["index"] not in observed_indices:
            observations.append({**row, "chunk": None, "oracle_registered": None, "candidate_registered": None, "both_observed": False, "registration_matches": None})
    observations.sort(key=lambda r: r["index"])
    after = {key: strict.sha256(path) for key, path in paths.items()}
    base_rows = [r for r in observations if r["origin"] == "base_internal_registration"]
    counts = Counter()
    for row in base_rows:
        a, b = row["oracle_registered"], row["candidate_registered"]
        counts["oracle_unobserved" if a is None else "oracle_registered" if a else "oracle_unregistered"] += 1
        counts["candidate_unobserved" if b is None else "candidate_registered" if b else "candidate_unregistered"] += 1
        if row["both_observed"]:
            counts["matching_registration" if row["registration_matches"] else "different_registration"] += 1
    report = {"schema_version": "1.0", "status": "NOT_COMPLETE", "finished_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "measurement": "function_exists registration observations; exact raw process stdout/stderr/status comparison; no normalization",
              "scope": "All names from actual official base internal-function profile plus2 explicit extras. Function bodies never invoked. Native-preloaded and other extension profiles not tested.",
              "registration_only": True, "function_implementation_verified": False,
              "php_full_compatible": False, "source_profile": str(profile_path),
              "inputs_before": before, "inputs_after": after, "inputs_unchanged": before == after,
              "chunk_name_cap": args.names_per_process, "max_source_chars": args.max_source_chars,
              "timeout_seconds": args.timeout, "base_name_count": len(functions), "extra_name_count": 2,
              "total_name_count": len(rows), "chunk_count": len(chunks), "executed_chunks": len(processes),
              "base_registration_counts": dict(counts),
              "extra_observations": [r for r in observations if r["origin"] != "base_internal_registration"],
              "all_names_both_observed": all(r["both_observed"] for r in observations),
              "strict_equal_chunks": sum(not r["strict_differences"] for r in processes),
              "operational_errors": operational_errors, "processes": processes, "observations": observations}
    (output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    reproduction = {"argv": [sys.executable, str(Path(__file__).resolve()), "--inventory", str(inventory), "--output", "NEW_OUTPUT_DIRECTORY", "--adapter", str(paths["adapter"]), "--php", str(paths["php"]), "--powershell", str(paths["powershell"]), "--max-source-chars", str(args.max_source_chars), "--names-per-process", str(args.names_per_process), "--timeout", str(args.timeout), "--sentinel", sentinel]}
    (output / "reproduce.json").write_text(json.dumps(reproduction, indent=2) + "\n", encoding="utf-8")
    (output / "observations.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in observations), encoding="utf-8")
    print(json.dumps({k: report[k] for k in ["base_name_count", "total_name_count", "base_registration_counts", "all_names_both_observed", "inputs_unchanged", "operational_errors"]}, ensure_ascii=True))
    # Registration differences are expected findings, not collection failures.
    return 0 if report["all_names_both_observed"] and before == after and not operational_errors else 2


if __name__ == "__main__":
    raise SystemExit(main())
