"""Independent stock-PHP/native-component runs; no fallback or case retries."""
import argparse
import base64
import hashlib
import json
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
PHP = Path("C:/Users/rinpa/ALL_php_oracle/php-8.5.12-ts-x64/php.exe")
EXTENSION = PHP.parent / "ext/php_dl_test.dll"
CORE = {
    "legacy": ROOT / "native/php85abi/out/windows-x64-ts/php8ts.dll",
    "callback": ROOT / "native/php85abi-callback/out/windows-x64-ts/php8ts.dll",
}
PINS = {
    PHP: "0ac893499799256db6d3a54b0da73692e02311493922e6e4f86a062674a77d66",
    EXTENSION: "532b9f0944d482a704eb81ac1cb9af3b59aa0f54c753c53a5709c17f57d4e938",
    CORE["legacy"]: "b2ffd9f38abd20894b064b53a94e4a05e5d39eaa2055e910db6d762558e46757",
    CORE["callback"]: "88117b8f38dc77d20e638ce573bb83fc6f959c1ad6821f8803c5499969fe234b",
    ROOT / "package/ALL_PHP_v3_12_adapter.ps1": "5856687f7abd1471b4af7af9827ca2d17a011e836ad2852bf1d7993298fddc9f",
    ROOT / "tools/candidates/php-callback-v3_20/AllNativeLegacyBridge.cs": "32692504898a77063bcbad631c48d40d8fa1f7c17fcf3f5d837c6f77479ec077",
    ROOT / "tools/candidates/php-callback-v3_20/AllNativeCallbackBridge.cs": "8c37470ecafa4c00a41dbf8917295f88f76b7d2fbbd57645a91313bc833efda8",
    ROOT / "tools/abi/DlTest-Cases.json": "a735c41233954eeb7cd49e0c690aa37985bb2634f37dd5517677b39832d18581",
    ROOT / "tools/candidates/php-byte-string/component.cases.json": "34f1a09d35bbeb1940710e38aa16458c5cb291ba4f2674dd06d93a01f47e45f4",
    ROOT / "tools/candidates/php-byte-string/component-extended.cases.json": "2a8b7ed386cec4d173cc45c9dded20a920f396dcd5a4b78e8f6335385fa149a7",
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def byte_argument(raw):
    return {"type": "bytes", "base64": base64.b64encode(raw).decode("ascii")}


def fixtures():
    result = []
    payloads = [
        ("empty", b""), ("ff", b"\xff"), ("nul", b"A\0B"),
        ("high80", b"\x80"), ("truncated_utf8", b"\xe3\x81"),
        ("overlong_utf8", b"\xc0\xaf"), ("surrogate_utf8", b"\xed\xa0\x80"),
        ("all256", bytes(range(256))), ("unicode_utf8", "日本語😀".encode("utf-8")),
        ("copy_chunk_seams", b"a" * 65535 + b"\xff\0" + bytes(range(256)) * 256),
    ]
    for name, raw in payloads:
        result.append({"id": name, "function": "dl_test_test2", "args": [byte_argument(raw)], "strict": False})
    result += [
        {"id": "weak_integer", "function": "dl_test_test2", "args": [{"type": "int", "value": "123"}], "strict": False},
        {"id": "strict_integer_typeerror", "function": "dl_test_test2", "args": [{"type": "int", "value": "123"}], "strict": True},
        {"id": "null_deprecation", "function": "dl_test_test2", "args": [{"type": "null"}], "strict": False, "callback_behavior": "capture"},
        {"id": "int64_minimum", "function": "dl_test_frameless", "args": [{"type": "int", "value": "-9223372036854775808"}], "strict": False},
        {"id": "int64_maximum", "function": "dl_test_frameless", "args": [{"type": "int", "value": "9223372036854775807"}], "strict": False},
        {"id": "old_api_utf8", "function": "dl_test_test2", "args": [{"type": "managed_text", "value": "日本語"}], "strict": False, "api": "InvokeScalar"},
        {"id": "old_api_diagnostic_handler", "function": "dl_test_test2", "args": [{"type": "null"}], "strict": False, "api": "InvokeScalar", "callback_behavior": "legacy_capture"},
        {"id": "managed_text_guard", "function": "dl_test_test2", "args": [{"type": "managed_text", "value": "not silently a PHP byte value"}], "strict": False, "managed_guard": True},
        {"id": "managed_lone_surrogate_guard", "function": "dl_test_test2", "args": [{"type": "managed_text", "value": "\ud800"}], "strict": False, "managed_guard": True},
        {"id": "raw_ini_module_output", "operation": "module_info", "function": "dl_test_test2", "args": [byte_argument(bytes(range(1,256)))], "strict": False},
    ]
    return result


def php_argument(item):
    kind = item["type"]
    if kind == "bytes":
        return "base64_decode('" + item["base64"] + "',true)"
    if kind == "managed_text":
        return "base64_decode('" + base64.b64encode(item["value"].encode("utf-8")).decode("ascii") + "',true)"
    if kind == "null":
        return "null"
    if kind == "int":
        # PHP_INT_MIN cannot be written as a positive out-of-range literal
        # followed by unary minus; construct the intended scalar explicitly.
        return "(int)'" + item["value"] + "'"
    if kind == "double":
        return item["value"]
    if kind == "bool":
        return "true" if item["value"] else "false"
    raise ValueError(kind)


def php_source(fixture):
    invocation = fixture["function"] + "(" + ",".join(php_argument(a) for a in fixture["args"]) + ")"
    prefix = ""
    if fixture.get("operation") == "module_info":
        prefix = "ini_set('dl_test.string'," + php_argument(fixture["args"][0]) + ");$record['ini_value_base64']=base64_encode(ini_get('dl_test.string'));(new ReflectionExtension('dl_test'))->info();"
        invocation = "null"
    return """<?php
declare(strict_types=STRICT);
$events=[];
set_error_handler(function($level,$message)use(&$events){$events[]=['level'=>$level,'message_base64'=>base64_encode($message)];return true;});
$record=['ok'=>true,'error_class'=>null,'error_message_base64'=>null];
try{PREFIX$value=INVOCATION;$record['value']=is_string($value)?['type'=>'string','value'=>base64_encode($value)]:(is_int($value)?['type'=>'int','value'=>(string)$value]:(is_null($value)?['type'=>'null','value'=>null]:['type'=>get_debug_type($value),'value'=>$value]));}
catch(Throwable $error){$record['ok']=false;$record['error_class']=get_class($error);$record['error_message_base64']=base64_encode($error->getMessage());$record['value']=['type'=>'null','value'=>null];}
$record['events']=$events;
file_put_contents($argv[1],json_encode($record,JSON_THROW_ON_ERROR));
""".replace("STRICT", "1" if fixture["strict"] else "0").replace("PREFIX", prefix).replace("INVOCATION", invocation)


def run(command, timeout):
    began = time.perf_counter()
    try:
        process = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
        return {"command": command, "state": "EXITED", "actual_status": process.returncode,
                "elapsed_seconds": time.perf_counter()-began,
                "stdout_base64": base64.b64encode(process.stdout).decode("ascii"),
                "stderr_base64": base64.b64encode(process.stderr).decode("ascii")}
    except subprocess.TimeoutExpired as error:
        return {"command": command, "state": "TIMEOUT", "actual_status": None,
                "elapsed_seconds": time.perf_counter()-began,
                "stdout_base64": base64.b64encode(error.stdout or b"").decode("ascii"),
                "stderr_base64": base64.b64encode(error.stderr or b"").decode("ascii")}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--build", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--timeout", type=float, default=30)
    options = parser.parse_args()
    build, output = Path(options.build).resolve(), Path(options.output).resolve()
    if output.exists():
        raise SystemExit("Preserve prior run; output must be fresh")
    output.mkdir(parents=True)
    host = build / "all-native-byte-probe.exe"
    inputs = dict(PINS)
    for path in [host, build / "AllPhp.NativeBytes.Bridges.dll", build / "AllPhp.ByteValues.Runtime.dll", build / "build.json", HERE / "AllNativeByteProbe.cs", Path(__file__)]:
        inputs[path] = digest(path)
    build_record = json.loads((build / "build.json").read_text(encoding="utf-8-sig"))
    assert build_record["inputs_before"] == build_record["inputs_after"]
    for label, path in build_record["input_paths"].items():
        inputs[Path(path)] = build_record["inputs_before"][label]
    for path, expected in inputs.items():
        assert digest(path) == expected, path
    before = {p.as_posix(): digest(p) for p in inputs}
    rows = []
    cases = fixtures()
    save(output / "fixtures.json", cases)
    for mode in ("legacy", "callback"):
        for index, fixture in enumerate(cases):
            prefix = output / (mode + "-" + str(index).zfill(3))
            fixture_path, own_meta, php_path, oracle_meta = [prefix.with_suffix(s) for s in (".fixture.json", ".native.json", ".php", ".oracle.json")]
            save(fixture_path, fixture)
            php_path.write_text("<?php // Managed boundary rejection; no PHP reference invoked.\n" if fixture.get("managed_guard") else php_source(fixture), encoding="utf-8", newline="\n")
            own_command = [str(host), mode, str(CORE[mode]), str(EXTENSION), str(fixture_path), str(own_meta), PINS[CORE[mode]], PINS[EXTENSION]]
            own = run(own_command, options.timeout)
            native = json.loads(own_meta.read_text(encoding="utf-8-sig")) if own_meta.exists() else None
            row = {"id": mode + "." + fixture["id"], "fixture_sha256": digest(fixture_path), "reference_source_sha256": digest(php_path), "candidate": own, "native_metadata": native, "differences": []}
            differences = row["differences"]
            if own["state"] != "EXITED" or own["actual_status"] != 0 or not native or "host_failure" in native or "cleanup_failure" in native:
                differences.append("own process/load/cleanup did not complete normally")
            if native:
                before_count = native["stats_before"]["native_invocations"]
                after_count = native["stats_after_call"]["native_invocations"]
                expected_delta = 0 if fixture.get("managed_guard") or fixture.get("operation") == "module_info" else 1
                if after_count-before_count != expected_delta:
                    differences.append("native invocation count differs; no retry allowed")
                final = native.get("stats_final", {})
                for a, b in (("minit", "mshutdown"), ("rinit", "rshutdown"), ("tls_contexts_created", "tls_contexts_destroyed")):
                    if final.get(a) != 1 or final.get(b) != 1:
                        differences.append("controlled lifecycle " + a + "/" + b)
                if final.get("request_allocations_live") != 0:
                    differences.append("tracked request allocations not zero")
                if native.get("returned_value_before_end") != native.get("returned_value_after_end"):
                    differences.append("returned byte value changed after native teardown")
                if mode == "callback" and native.get("callback_stats_final", {}).get("callback_owner_thread") != 0:
                    differences.append("callback lease not cleared")
            if fixture.get("managed_guard"):
                if not native or native.get("managed_exception") != "System.NotSupportedException":
                    differences.append("managed string was not rejected explicitly")
                row["verdict"] = "EXPECTED_MANAGED_BOUNDARY_REJECTION" if not differences else "FAIL"
            else:
                oracle = run([str(PHP), "-n", "-d", "extension=" + str(EXTENSION), "-d", "display_errors=stderr", "-d", "error_reporting=-1", "-d", "date.timezone=UTC", str(php_path), str(oracle_meta)], options.timeout)
                reference = json.loads(oracle_meta.read_text(encoding="utf-8-sig")) if oracle_meta.exists() else None
                row["oracle"], row["oracle_metadata"] = oracle, reference
                if oracle["state"] != "EXITED" or oracle["actual_status"] != 0 or not reference:
                    differences.append("reference did not complete normally")
                if own["stdout_base64"] != oracle["stdout_base64"] or own["stderr_base64"] != oracle["stderr_base64"]:
                    differences.append("raw stdout/stderr bytes differ")
                if native and reference:
                    for key in ("ok", "value", "error_class", "error_message_base64", "events"):
                        if native.get(key) != reference.get(key):
                            differences.append(key)
                    if fixture.get("operation") == "module_info" and native.get("ini_value_base64") != reference.get("ini_value_base64"):
                        differences.append("raw INI value bytes")
                    if fixture.get("api") != "InvokeScalar" and reference["ok"] and reference["value"]["type"] == "string" and native.get("value_model") != "AllPhp.ByteValues.PhpBytes":
                        differences.append("PHP string return was not canonical PhpBytes")
                    if mode == "callback" and fixture.get("callback_behavior") in ("capture", "legacy_capture") and native.get("callbacks") != reference["events"]:
                        differences.append("synchronous byte diagnostic delivery")
                row["verdict"] = "PASS" if not differences else "FAIL"
            rows.append(row)
            print(row["verdict"] + ": " + row["id"] + (" " + repr(differences) if differences else ""), flush=True)
            save(output / "report.partial.json", {"status": "IN_PROGRESS", "results": rows})
    after = {p.as_posix(): digest(p) for p in inputs}
    report = {"status": "SELECTED_BYTE_NATIVE_COMPONENT_PROFILE_NOT_FULL_PHP", "inputs_before": before, "inputs_after": after, "inputs_unchanged": before == after, "timeout_seconds": options.timeout, "driver_argv": sys.argv, "native_function_retries": 0, "passed": sum(r["verdict"] == "PASS" for r in rows), "guard_rejections": sum(r["verdict"] == "EXPECTED_MANAGED_BOUNDARY_REJECTION" for r in rows), "failed": sum(r["verdict"] == "FAIL" for r in rows), "results": rows}
    save(output / "report.json", report)
    print(json.dumps({k: report[k] for k in ("passed", "guard_rejections", "failed", "inputs_unchanged")}))
    return 0 if report["failed"] == 0 and report["inputs_unchanged"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
