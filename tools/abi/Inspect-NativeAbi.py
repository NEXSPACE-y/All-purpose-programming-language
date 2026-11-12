#!/usr/bin/env python3
"""Inspect PHP extension PE files without importing or executing any DLL.

Only the Python standard library is used. Import inventories are a lower bound:
GetProcAddress calls, inlined structure access and runtime behaviour are not inferred.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import re
import struct
import zipfile


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class PE:
    def __init__(self, path: Path):
        self.path = path
        self.data = path.read_bytes()
        if self.data[:2] != b"MZ":
            raise ValueError(f"Not a PE file: {path}")
        pe = self.u32(0x3C)
        if self.data[pe:pe + 4] != b"PE\0\0":
            raise ValueError(f"Invalid PE signature: {path}")
        self.machine, count, self.timestamp = struct.unpack_from("<HHI", self.data, pe + 4)
        size = self.u16(pe + 20)
        optional = pe + 24
        self.magic = self.u16(optional)
        if self.magic != 0x20B:
            raise ValueError(f"This inspection supports PE32+ only: {path}")
        self.image_base = self.u64(optional + 24)
        self.header_size = self.u32(optional + 60)
        self.linker = f"{self.data[optional + 2]}.{self.data[optional + 3]}"
        self.directories = [struct.unpack_from("<II", self.data, optional + 112 + 8 * i)
                            for i in range(min(16, self.u32(optional + 108)))]
        self.sections = []
        for i in range(count):
            off = optional + size + i * 40
            name = self.data[off:off + 8].split(b"\0", 1)[0].decode("ascii")
            virtual_size, rva, raw_size, raw = struct.unpack_from("<IIII", self.data, off + 8)
            self.sections.append(dict(name=name, rva=rva, virtual_size=virtual_size,
                                      raw_size=raw_size, raw=raw, flags=self.u32(off + 36)))

    def u16(self, off): return struct.unpack_from("<H", self.data, off)[0]
    def u32(self, off): return struct.unpack_from("<I", self.data, off)[0]
    def u64(self, off): return struct.unpack_from("<Q", self.data, off)[0]

    def offset(self, rva):
        if rva < self.header_size:
            return rva
        for sec in self.sections:
            delta = rva - sec["rva"]
            if 0 <= delta < sec["raw_size"]:
                return sec["raw"] + delta
        raise ValueError(f"RVA {rva:#x} has no file-backed bytes in {self.path.name}")

    def string(self, rva):
        off = self.offset(rva)
        return self.data[off:self.data.index(b"\0", off)].decode("utf-8", errors="replace")

    def pointer_string(self, va):
        return self.string(va - self.image_base) if va else None

    def directory(self, index):
        return self.directories[index] if index < len(self.directories) else (0, 0)

    def thunk_symbols(self, table):
        symbols = []
        for i in range(100000):
            val = self.u64(self.offset(table + 8 * i))
            if not val:
                return symbols
            if val & (1 << 63):
                symbols.append({"ordinal": val & 0xFFFF})
            else:
                symbols.append({"name": self.string(val + 2)})
        raise ValueError("Unterminated import thunk")

    def imports(self):
        found = []
        for delay in (False, True):
            rva, size = self.directory(13 if delay else 1)
            if not rva:
                continue
            width = 32 if delay else 20
            for i in range(size // width + 1):
                off = self.offset(rva + width * i)
                row = struct.unpack_from("<8I" if delay else "<5I", self.data, off)
                if not any(row):
                    break
                if delay:
                    attr, name, _, iat, table, _, _, _ = row
                    if not (attr & 1):
                        name -= self.image_base
                        table -= self.image_base
                else:
                    table, _, _, name, iat = row
                    table = table or iat
                found.append({"dll": self.string(name), "delay_load": delay,
                              "symbols": self.thunk_symbols(table)})
        return found

    def exports(self):
        rva, size = self.directory(0)
        if not rva:
            return []
        off = self.offset(rva)
        base, nfunc, nname, funcs, names, ordinals = struct.unpack_from("<6I", self.data, off + 16)
        named = {}
        for i in range(nname):
            name = self.string(self.u32(self.offset(names + 4 * i)))
            index = self.u16(self.offset(ordinals + 2 * i))
            named.setdefault(index, []).append(name)
        found = []
        for i in range(nfunc):
            target = self.u32(self.offset(funcs + 4 * i))
            if not target:
                continue
            sec = next((s for s in self.sections
                        if s["rva"] <= target < s["rva"] + max(s["raw_size"], s["virtual_size"])), None)
            row = {"ordinal": base + i, "names": named.get(i, []), "rva": target,
                   "section": sec["name"] if sec else None,
                   "kind": "code" if sec and sec["flags"] & 0x20 else "data"}
            if rva <= target < rva + size:
                row.update(kind="forwarder", forwarder=self.string(target))
            found.append(row)
        return found

    def module_metadata(self, exports):
        exported = next((e for e in exports if "get_module" in e["names"]), None)
        if exported is None:
            return {"status": "no_get_module_export"}
        rva = exported["rva"]
        off = self.offset(rva)
        code = self.data[off:off + 16]
        # MSVC x64 get_module(): lea rax,[rip+disp32]; ret.
        if code[:3] == b"\x48\x8d\x05" and code[7] == 0xC3:
            entry = rva + 7 + struct.unpack_from("<i", code, 3)[0]
        else:
            return {"status": "stub_not_recognised", "get_module_rva": rva,
                    "first_16_bytes": code.hex()}
        pos = self.offset(entry)
        declared_size = self.u16(pos)
        # Offsets are for the actual MSVC x64 header. Verify with Abi-Layout.c.
        return {"status": "statically_decoded", "method": "lea_rax_rip_ret_no_execution",
                "module_entry_rva": entry, "size": declared_size,
                "zend_api": self.u32(pos + 4), "zend_debug": self.data[pos + 8],
                "zts": self.data[pos + 9],
                "name": self.pointer_string(self.u64(pos + 32)),
                "version": self.pointer_string(self.u64(pos + 88)),
                "build_id": self.pointer_string(self.u64(pos + 160)),
                "has_module_startup": bool(self.u64(pos + 48)),
                "has_request_startup": bool(self.u64(pos + 64)),
                "globals_size": self.u64(pos + 96)}

    def inspect(self, root):
        exports = self.exports()
        return {"path": str(self.path.resolve()), "relative_path": self.path.relative_to(root).as_posix(),
                "size_bytes": len(self.data), "sha256": hashlib.sha256(self.data).hexdigest(),
                "machine": f"0x{self.machine:04x}", "pe_format": "PE32+", "linker_version": self.linker,
                "image_base": self.image_base, "imports": self.imports(), "exports": exports,
                "module": self.module_metadata(exports)}


def zip_evidence(path: Path, wanted: list[str]):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        members = []
        for suffix in wanted:
            matches = [n for n in names if n == suffix or n.endswith("/" + suffix)]
            for name in matches:
                data = archive.read(name)
                members.append({"path": name, "size_bytes": len(data),
                                "sha256": hashlib.sha256(data).hexdigest()})
        return {"path": str(path.resolve()), "size_bytes": path.stat().st_size,
                "sha256": sha256(path), "member_count": len(names), "selected_members": members}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--source-zip", type=Path, required=True)
    parser.add_argument("--devel-zip", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = args.runtime.resolve()
    files = [root / "php8ts.dll", *sorted((root / "ext").glob("*.dll"))]
    images = [PE(path).inspect(root) for path in files]
    core = images[0]
    core_symbols = {name: export["kind"] for export in core["exports"] for name in export["names"]}
    extensions = images[1:]
    imported = {}
    dependency_names = set()
    for image in extensions:
        for group in image["imports"]:
            dependency_names.add(group["dll"].lower())
            if group["dll"].lower() != "php8ts.dll":
                continue
            for symbol in group["symbols"]:
                name = symbol.get("name", f"ordinal:{symbol.get('ordinal')}")
                imported.setdefault(name, []).append(image["relative_path"])
    data_imports = {s: users for s, users in imported.items() if core_symbols.get(s) == "data"}
    metadata = [i["module"] for i in extensions if i["module"]["status"] == "statically_decoded"]
    wanted = ["Zend/zend_modules.h", "Zend/zend_types.h", "Zend/zend_API.h", "Zend/zend_compile.h",
              "Zend/zend_globals.h", "Zend/zend_extensions.h", "Zend/zend_object_handlers.h",
              "Zend/zend_portability.h", "Zend/zend_build.h", "TSRM/TSRM.h",
              "main/config.w32.h", "main/php_version.h", "ext/standard/dl.c", "ext/dl_test/dl_test.c"]
    report = {
        "schema_version": 1,
        "generated_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "method": "static_file_bytes_only_python_standard_library",
        "php_or_extension_code_loaded_or_executed": False,
        "limitations": ["PE imports are a lower bound, not the complete runtime ABI contract",
                        "GetProcAddress, inline structure access and runtime behaviour are not inferred",
                        "Only inventoried local binaries are covered; no third-party binary compatibility was executed",
                        "get_module metadata is decoded only for a recognised x64 instruction stub"],
        "summary": {"extension_dll_count": len(extensions), "core_named_exports": len(core_symbols),
                    "extension_unique_php8ts_imports": len(imported), "imported_core_data_symbols": len(data_imports),
                    "unmatched_named_core_imports": sorted(s for s in imported if s not in core_symbols),
                    "decoded_module_count": len(metadata),
                    "module_api_values": sorted({m["zend_api"] for m in metadata}),
                    "module_entry_sizes": sorted({m["size"] for m in metadata}),
                    "module_build_ids": sorted({m["build_id"] for m in metadata}),
                    "module_zts_values": sorted({m["zts"] for m in metadata}),
                    "module_debug_values": sorted({m["zend_debug"] for m in metadata}),
                    "dependency_dlls": sorted(dependency_names)},
        "php8ts_import_users": dict(sorted(imported.items())),
        "php8ts_data_import_users": dict(sorted(data_imports.items())),
        "archives": [zip_evidence(args.source_zip, wanted), zip_evidence(args.devel_zip, wanted + ["lib/php8ts.lib"])],
        "images": images,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(args.output.resolve()), "summary": report["summary"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
