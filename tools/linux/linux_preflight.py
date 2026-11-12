"""Read-only Linux environment discovery; never starts/provisions a backend.

Writes only the explicitly requested JSON report. No SSH connection, credential
inspection, package install, WSL launch/import, container or VM start is made.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import os
import platform
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def decode(raw):
    if not raw:
        return {"encoding": "none", "text": ""}
    encodings = ["utf-16-le", "utf-8", "cp932"] if b"\0" in raw[:64] else ["utf-8", "cp932"]
    for encoding in encodings:
        try:
            return {"encoding": encoding, "text": raw.decode(encoding)}
        except UnicodeError:
            pass
    return {"encoding": "hex", "text": raw.hex()}


def probe(argv, timeout=12):
    try:
        result = subprocess.run(argv, cwd=ROOT, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=timeout, check=False)
        return {"argv": argv, "exit_code": result.returncode,
                "stdout": decode(result.stdout), "stderr": decode(result.stderr),
                "stdout_sha256": hashlib.sha256(result.stdout).hexdigest(),
                "stderr_sha256": hashlib.sha256(result.stderr).hexdigest()}
    except (OSError, subprocess.TimeoutExpired) as error:
        return {"argv": argv, "error": type(error).__name__, "detail": str(error)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path,
                        default=ROOT / "reports/linux-preflight-20261112.json")
    args = parser.parse_args()
    names = ["wsl", "docker", "podman", "ssh", "scp", "qemu-system-x86_64",
             "VBoxManage", "vmrun", "multipass", "pwsh", "cmake", "ninja",
             "clang", "clang-cl", "gcc", "g++", "cc", "c++", "make", "php",
             "python3", "readelf", "ldd"]
    tools = {name: shutil.which(name) for name in names}
    observations = []
    windows = platform.system() == "Windows"
    if windows:
        if tools["wsl"]:
            observations += [probe([tools["wsl"], "--list", "--verbose"]),
                             probe([tools["wsl"], "--status"])]
        if tools["docker"]:
            observations += [probe([tools["docker"], "--version"]),
                             probe([tools["docker"], "context", "ls", "--format", "json"])]
        if tools["podman"]:
            observations += [probe([tools["podman"], "--version"]),
                             probe([tools["podman"], "machine", "list", "--format", "json"])]
        if tools["ssh"]:
            observations.append(probe([tools["ssh"], "-V"]))
        shell = Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32/WindowsPowerShell/v1.0/powershell.exe"
        if shell.is_file():
            command = (
                "$ErrorActionPreference='SilentlyContinue';"
                "$s=@(Get-Service -Name WslService,LxssManager,vmcompute,'com.docker.service' | Select-Object Name,Status,StartType);"
                "$p=@(Get-Process -Name 'vmware-vmx','VirtualBoxVM','VBoxHeadless','qemu*','wsl*','vmmem*','docker','podman' | Select-Object Name,Id);"
                "$h=@(Get-Command Get-VM | Select-Object Name,Source);"
                r"[pscustomobject]@{services=$s;processes=$p;hyperv_cmdlets=$h;lxss_registry_present=(Test-Path -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss')} | ConvertTo-Json -Depth 4 -Compress"
            )
            observations.append(probe([str(shell), "-NoProfile", "-NonInteractive", "-Command", command], timeout=20))
    else:
        observations += [probe(["uname", "-a"]), probe(["getconf", "LONG_BIT"])]
        for name in ["cc", "c++", "cmake", "ninja", "make", "pwsh", "php"]:
            if tools[name]:
                observations.append(probe([tools[name], "--version"]))
    oracle = Path.home() / "ALL_php_oracle"
    locations = [oracle, Path(r"C:\Program Files\Docker"),
                 Path(r"C:\Program Files\Oracle\VirtualBox"),
                 Path(r"C:\Program Files\qemu"), Path(r"C:\Program Files\VMware")]
    known_paths = [{"path": str(p), "exists": p.exists(),
                    "children": sorted(x.name for x in p.iterdir()) if p.is_dir() else []}
                   for p in locations if windows or p == oracle]
    tracked = probe(["git", "ls-files"])
    files = tracked.get("stdout", {}).get("text", "").splitlines()
    relevant = [name for name in files if "linux" in name.lower() or
                name.lower().split("/")[-1].startswith("dockerfile") or
                name.lower().endswith((".qcow2", ".vhdx", ".ova", ".ovf"))]
    distro = {}
    if platform.system() == "Linux":
        try:
            distro = platform.freedesktop_os_release()
        except (OSError, AttributeError):
            pass
    report = {
        "schema_version": "1.0", "status": "NOT_COMPLETE",
        "generated_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "host": {"system": platform.system(), "release": platform.release(),
                 "version": platform.version(), "machine": platform.machine(),
                 "libc": platform.libc_ver() if platform.system() == "Linux" else None,
                 "linux_distribution": distro},
        "workspace": str(ROOT), "tools_on_path": tools,
        "read_only_probes": observations, "known_locations": known_paths,
        "tracked_linux_or_backend_candidates": relevant,
        "native_candidate_directory_exists": (ROOT / "native/php85abi").is_dir(),
        "linux_runtime_discovered": platform.system() == "Linux",
        "linux_build_validated": False, "linux_native_execution_validated": False,
        "linux_php_8_5_12_oracle_verified": False,
        "linux_web_sapi_validated": False,
        "ssh_endpoint_selected_or_contacted": False,
        "limitations": [
            "PATH, named default program directories, scoped workspace and read-only backend inventories only; not an exhaustive machine search.",
            "An installed SSH client proves no Linux endpoint or connection.",
            "An installed WSL launcher proves no installed feature/distro.",
            "Existing Linux scripts and Windows build/header artifacts prove no Linux execution.",
            "No backend started/imported, dependency installed, package downloaded, service restarted, credential read or remote connection attempted."
        ]}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"report": str(args.output), "host": report["host"],
                      "linux_runtime_discovered": report["linux_runtime_discovered"],
                      "linux_native_execution_validated": False}, ensure_ascii=True))


if __name__ == "__main__":
    main()
