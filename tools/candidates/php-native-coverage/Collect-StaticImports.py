"""Static PE/dumpbin inventory only; never load PHP/extension DLLs."""
from pathlib import Path
import argparse
import datetime
import hashlib
import importlib.util
import json
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
ORACLE = Path("C:/Users/rinpa/ALL_php_oracle/php-8.5.12-ts-x64")
DUMPBIN = Path("C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC/14.44.35207/bin/Hostx64/x64/dumpbin.exe")
CORES = {
    "original": (ROOT / "native/php85abi/out/windows-x64-ts/php8ts.dll", "b2ffd9f38abd20894b064b53a94e4a05e5d39eaa2055e910db6d762558e46757"),
    "callback": (ROOT / "native/php85abi-callback/out/windows-x64-ts/php8ts.dll", "88117b8f38dc77d20e638ce573bb83fc6f959c1ad6821f8803c5499969fe234b"),
}
INSPECTOR = ROOT / "tools/abi/Inspect-NativeAbi.py"
spec = importlib.util.spec_from_file_location("pe_static", INSPECTOR)
pe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pe)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists():
        parser.error("Preserve prior collection; choose a fresh output directory")
    if not DUMPBIN.is_file():
        parser.error("Pinned existing dumpbin was not found; no installation attempted")
    for path, expected in CORES.values():
        assert digest(path) == expected, path
    extensions = sorted((ORACLE / "ext").glob("*.dll"))
    assert extensions, "No fixed-oracle DLLs"
    sources = [ROOT / ("native/" + name + "/src/Runtime.cpp") for name in ("php85abi", "php85abi-callback")]
    headers = [ROOT / ("native/" + name + "/include/all_php_bridge.h") for name in ("php85abi", "php85abi-callback")]
    paths = [DUMPBIN, INSPECTOR, Path(__file__).resolve(), ORACLE / "php8ts.dll", ORACLE / "php.exe", *extensions, *sources, *headers, *(p for p, _ in CORES.values())]
    before = {p.as_posix(): digest(p) for p in paths}
    output.mkdir(parents=True)
    raw = output / "dumpbin"
    raw.mkdir()
    processes = []

    def dump(path, operation, label):
        command = [str(DUMPBIN), "/NOLOGO", operation, str(path)]
        result = subprocess.run(command, cwd=ROOT, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
        stdout_path, stderr_path = raw / (label + ".stdout.bin"), raw / (label + ".stderr.bin")
        stdout_path.write_bytes(result.stdout); stderr_path.write_bytes(result.stderr)
        item = {"command":command,"actual_status":result.returncode,"stdout_path":stdout_path.relative_to(output).as_posix(),"stdout_sha256":digest(stdout_path),"stderr_path":stderr_path.relative_to(output).as_posix(),"stderr_sha256":digest(stderr_path),"inspected_file_sha256":digest(path)}
        processes.append(item)
        assert result.returncode == 0, item
        return result.stdout

    core_results = {}
    for label, (path, pin) in CORES.items():
        image = pe.PE(path)
        exports = image.exports()
        dump(path,"/EXPORTS",label + "-core-exports")
        dump(path,"/IMPORTS",label + "-core-imports")
        core_results[label] = {"path":path.as_posix(),"sha256":pin,"machine":image.machine,"exports":exports,"imports":image.imports()}
    stock = pe.PE(ORACLE / "php8ts.dll")
    stock_exports = stock.exports()
    dump(ORACLE / "php8ts.dll","/EXPORTS","oracle-core-exports")
    exported_names = {mode:{name for item in value["exports"] for name in item["names"]} for mode,value in core_results.items()}
    stock_by_name = {name:item for item in stock_exports for name in item["names"]}
    rows, requirements = [], {}
    for path in extensions:
        image = pe.PE(path)
        imports = image.imports()
        raw_imports = dump(path,"/IMPORTS",path.stem + "-imports")
        php_imports = [item for item in imports if item["dll"].lower() == "php8ts.dll"]
        names, ordinals = set(), set()
        for group in php_imports:
            for symbol in group["symbols"]:
                if "name" in symbol:
                    name = symbol["name"]
                    encoded = name.encode("ascii", "strict")
                    assert encoded in raw_imports, (path.name,name,"not independently visible in dumpbin")
                    names.add(name)
                    requirements.setdefault(name, {"oracle_export_kind":stock_by_name.get(name,{}).get("kind"),"imported_by":[]})["imported_by"].append(path.name)
                else:
                    ordinals.add(symbol["ordinal"])
        if php_imports:
            assert b"php8ts.dll" in raw_imports.lower()
        row = {"file":path.name,"path":path.as_posix(),"bytes":path.stat().st_size,"sha256":digest(path),"machine":image.machine,"pe_magic":image.magic,
               "imports":imports,"php8ts_named_imports":sorted(names),"php8ts_ordinal_imports":sorted(ordinals),
               "module_metadata":image.module_metadata(image.exports()),
               "own_name_presence":{mode:{"present_names":sorted(names & available),"missing_names":sorted(names - available),"all_named_imports_present":names <= available,
                                          "meaning_compatibility":"NOT_INFERRED_FROM_NAME_PRESENCE"}for mode,available in exported_names.items()}}
        rows.append(row)
    for name, requirement in requirements.items():
        requirement["imported_by"] = sorted(set(requirement["imported_by"]))
        requirement["present_in_own_exports"] = {mode:name in names for mode,names in exported_names.items()}
    after = {p.as_posix(): digest(p) for p in paths}
    assert before == after
    report = {"status":"STATIC_DEPENDENCY_INVENTORY_NOT_LOAD_OR_COMPATIBILITY_PROOF","generated_at_utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "extensions_loaded_or_executed":False,"stock_php_executed":False,"new_installations":False,"existing_core_modified":False,
              "method":"Existing dumpbin raw imports/exports plus independent static PE parser; no LoadLibrary/get_module call",
              "input_hashes_before":before,"input_hashes_after":after,"inputs_unchanged":True,
              "summary":{"extension_dlls":len(rows),"unique_php8ts_import_names":len(requirements),"imported_data_names":sum(item["oracle_export_kind"]=="data" for item in requirements.values()),
                         "own_export_names":{mode:len(names)for mode,names in exported_names.items()},
                         "oracle_export_names":len(stock_by_name)},"cores":core_results,"oracle_core_exports":stock_exports,"extensions":rows,"requirements":requirements,"dumpbin_processes":processes,
              "limits":["Name presence is not semantic implementation or load success","Inline struct access, dynamic GetProcAddress, callback and lifetime contracts are additional requirements","Bundled Windows x64 TS oracle DLLs only; Linux and absent third-party binaries unmeasured"]}
    save(output / "inventory.json",report)
    print(json.dumps(report["summary"]))


if __name__ == "__main__":
    main()
