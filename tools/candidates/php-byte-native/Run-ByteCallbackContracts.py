"""One controlled contract process; synthetic checks are not PHP conformance."""
import argparse
import base64
import hashlib
import json
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CORE = ROOT / "native/php85abi-callback/out/windows-x64-ts/php8ts.dll"
EXTENSION = Path("C:/Users/rinpa/ALL_php_oracle/php-8.5.12-ts-x64/ext/php_dl_test.dll")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--build", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--timeout", type=float, default=30)
    args = parser.parse_args()
    build, output = Path(args.build).resolve(), Path(args.output).resolve()
    if output.exists():
        raise SystemExit("Preserve prior run; output must be fresh")
    output.mkdir(parents=True)
    record = json.loads((build / "build.json").read_text(encoding="utf-8-sig"))
    inputs = {Path(p): record["inputs_before"][label] for label, p in record["input_paths"].items()}
    for item in record["files"]:
        inputs[build / item["path"]] = item["sha256"]
    inputs[CORE] = "88117b8f38dc77d20e638ce573bb83fc6f959c1ad6821f8803c5499969fe234b"
    inputs[EXTENSION] = "532b9f0944d482a704eb81ac1cb9af3b59aa0f54c753c53a5709c17f57d4e938"
    for path, expected in inputs.items():
        assert digest(path) == expected, path
    inputs[Path(__file__)] = digest(Path(__file__))
    before = {p.as_posix(): digest(p) for p in inputs}
    command = [str(build / "all-byte-callback-contract-probe.exe"), str(CORE), str(EXTENSION), str(output / "contract.json"), inputs[CORE], inputs[EXTENSION]]
    began = time.perf_counter()
    try:
        process = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=args.timeout)
        stdout, stderr, state, status = process.stdout, process.stderr, "EXITED", process.returncode
    except subprocess.TimeoutExpired as error:
        stdout, stderr, state, status = error.stdout or b"", error.stderr or b"", "TIMEOUT", None
    after = {p.as_posix(): digest(p) for p in inputs}
    (output / "stdout.bin").write_bytes(stdout)
    (output / "stderr.bin").write_bytes(stderr)
    native = json.loads((output / "contract.json").read_text(encoding="utf-8-sig")) if (output / "contract.json").exists() else None
    report = {"status": "CONTROLLED_CONTRACT_EVIDENCE_NOT_PHP_COMPATIBILITY", "driver_argv": sys.argv,
              "command": command, "state": state, "actual_status": status, "elapsed_seconds": time.perf_counter()-began,
              "timeout_seconds": args.timeout, "stdout_base64": base64.b64encode(stdout).decode("ascii"),
              "stderr_base64": base64.b64encode(stderr).decode("ascii"), "inputs_before": before,
              "inputs_after": after, "inputs_unchanged": before == after, "contract": native,
              "pass": state == "EXITED" and status == 0 and native is not None and native["status"] == "CONTROLLED_CONTRACT_PASS_NOT_PHP_COMPATIBILITY" and before == after}
    save(output / "process.json", report)
    print(json.dumps({"pass": report["pass"], "state": state, "actual_status": status, "checks": native.get("passed_checks") if native else None, "inputs_unchanged": before == after}))
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
