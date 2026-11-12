"""Build a minimal private-prelude-binding candidate; never edits its base."""
from pathlib import Path
import argparse
import difflib
import hashlib
import json

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--base", type=Path, default=ROOT / "tools/candidates/php-native/ALL_PHP_native_candidate.ps1")
args = parser.parse_args()
base = args.base.resolve(strict=True)
raw = base.read_bytes()
digest = hashlib.sha256(raw).hexdigest()
allowed = {"6cfde5e729ff594741b6bb3a254a5bcbd25c2a1ef62f2ad4c9f2b9642b1efb8a",
           "47c8edb9e39bffe3ed5475f2aeed7e36673a798d2f72baf0cb60abc39695322d"}
if digest not in allowed:
    raise SystemExit("Unreviewed base hash; stop instead of silently rebasing.")
before = raw.decode("utf-8-sig").replace("\r\n", "\n")
value = before
edits = []


def replace(old, new):
    global value
    count = value.count(old)
    if count != 1:
        raise ValueError((count, old[:120]))
    value = value.replace(old, new)
    edits.append({"anchor": old[:120], "matches": count})


replace("                NamespaceFallbacks = [System.Collections.Generic.Dictionary[int,string]]::new()\n",
        "                NamespaceFallbacks = [System.Collections.Generic.Dictionary[int,string]]::new()\n"
        "                ParsingInternalPrelude = $false\n")
replace("'explode','implode','__all_throwable_string','print_r'", "'explode','implode','print_r'")
replace("""                    $callArgs = Read-Arguments
                    return [pscustomobject]@{ Kind='call'; Name=$token; Args=@($callArgs); Fallback=$fallbackName; ResolvedName=$null }""", """                    $callArgs = Read-Arguments
                    # Only the engine-owned prelude can create this opcode. A
                    # user function with this spelling remains an ordinary call.
                    if ($state.ParsingInternalPrelude -and $token -ceq '__all_throwable_string') {
                        if ($callArgs.Count -ne 1) { throw 'ALL PHP: Invalid internal Throwable formatting call' }
                        return [pscustomobject]@{ Kind='internal_throwable_string'; Object=$callArgs[0] }
                    }
                    return [pscustomobject]@{ Kind='call'; Name=$token; Args=@($callArgs); Fallback=$fallbackName; ResolvedName=$null }""")
replace("                $savedFallbacks = $state.NamespaceFallbacks\n",
        "                $savedFallbacks = $state.NamespaceFallbacks\n"
        "                $savedPreludeParsing = $state.ParsingInternalPrelude\n")
replace("                    $state.NamespaceFallbacks = [System.Collections.Generic.Dictionary[int,string]]::new()\n",
        "                    $state.NamespaceFallbacks = [System.Collections.Generic.Dictionary[int,string]]::new()\n"
        "                    $state.ParsingInternalPrelude = $true\n")
replace("                    $state.NamespaceFallbacks = $savedFallbacks\n",
        "                    $state.NamespaceFallbacks = $savedFallbacks\n"
        "                    $state.ParsingInternalPrelude = $savedPreludeParsing\n")
if value.count("$script:ALLPhpPreludeAst") != 3:
    raise ValueError("Unexpected prelude cache references")
value = value.replace("$script:ALLPhpPreludeAst", "$script:ALLPhpPreludeAstPrivateThrowableV1")
edits.append({"anchor": "$script:ALLPhpPreludeAst", "matches": 3,
              "reason": "Versioned private AST cache cannot reuse a prior public-call AST."})
replace("                '__all_throwable_string' { return (Get-PhpThrowableString $callArgs[0]) }\n", "")
replace("                'literal' { return $node.Value }", """                'literal' { return $node.Value }
                'internal_throwable_string' {
                    return (Get-PhpThrowableString (Invoke-PhpExpr $node.Object))
                }""")
candidate = HERE / "ALL_PHP_private_throwable_candidate.ps1"
candidate.write_text(value, encoding="utf-8-sig")
(HERE / "base-adapter.snapshot.ps1").write_bytes(raw)
patch = "".join(difflib.unified_diff(raw.decode('utf-8-sig').splitlines(True), candidate.read_bytes().decode('utf-8-sig').splitlines(True),
    fromfile="a/package/ALL_PHP_v3_12_adapter.ps1", tofile="b/package/ALL_PHP_v3_12_adapter.ps1"))
(HERE / "private-throwable.patch").write_text(patch, encoding="utf-8", newline="\n")
provenance = {"status": "ISOLATED_PRIVATE_THROWABLE_CANDIDATE_NOT_COMPLETE",
              "base_path": str(base), "base_sha256": digest,
              "candidate_path": str(candidate), "candidate_sha256": hashlib.sha256(candidate.read_bytes()).hexdigest(),
              "base_mutated": hashlib.sha256(base.read_bytes()).hexdigest() != digest,
              "package_written": False, "edits": edits,
              "binding": "Prelude-only parser flag creates private AST opcode; evaluator calls formatter directly.",
              "cache_key": "ALLPhpPreludeAstPrivateThrowableV1",
              "retained_scope": "Existing CLI/default/native paths preserved; no new dependency or runtime delegation."}
(HERE / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n", encoding="utf-8")
print(json.dumps(provenance))
