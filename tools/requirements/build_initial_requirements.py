"""Build the initial requirements AUDIT from immutable commit 9d81717.

This reads Git objects and existing reports; it never executes PHP/ALL or updates
runtime code. It deliberately cannot generate a complete/100-percent claim.
Run from the repository root: python tools/requirements/build_initial_requirements.py
"""
from collections import Counter
from pathlib import Path
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
BASE = subprocess.check_output(
    ["git", "rev-parse", "9d81717^{commit}"], cwd=ROOT, text=True
).strip()
ADAPTER = "package/ALL_PHP_v3_12_adapter.ps1"
PHPT = "reports/PHPT_CORE_ALL_v3_16.jsonl"


def data(path):
    return subprocess.check_output(["git", "show", BASE + ":" + path], cwd=ROOT)


def text(path):
    return data(path).decode("utf-8-sig")


def sha(path):
    return hashlib.sha256(data(path)).hexdigest()


def manual(page):
    return "https://www.php.net/manual/en/" + page + ".php"


def source(path, directory=False):
    return "https://github.com/php/php-src/" + ("tree" if directory else "blob") + "/php-8.5.12/" + path


PHPT_ROWS = [json.loads(line) for line in text(PHPT).splitlines() if line.strip()]
REQUIREMENTS = []


def add(id, parent, title, page, spans="", fixtures=(), pattern=None,
        state=None, remaining=None, kind="leaf", stage=1, dependencies=()):
    implementation = []
    for span in spans.split(",") if spans else []:
        start, end = (int(x) for x in span.split("-"))
        implementation.append({"path": ADAPTER, "start_line": start,
                               "end_line": end, "baseline_commit": BASE})
    tests = []
    for file, name_pattern in fixtures:
        path = "package/" + file
        cases = json.loads(text(path))
        selected = [x for x in cases if name_pattern is None or re.search(name_pattern, x["name"], re.I)]
        if not selected:
            raise ValueError((file, name_pattern))
        tests += [{"path": path, "id": x["name"], "kind": "fixture"} for x in selected[:3]]
    observations = []
    if pattern:
        selected = [x for x in PHPT_ROWS if re.search(pattern, x["test"].replace("\\", "/"), re.I)]
        observations.append({"path": PHPT, "selection_regex": pattern,
                             "selected_count": len(selected),
                             "verdict_counts": dict(Counter(x["verdict"] for x in selected)),
                             "quality": "Historical normalized output only; not semantic verification."})
        tests += [{"path": x["test"].replace("\\", "/"),
                   "id": x["test"].replace("\\", "/"), "kind": "official_phpt",
                   "recorded_verdict": x["verdict"],
                   "source_url": source(x["test"].replace("\\", "/"))}
                  for x in selected[:3]]
    url = page if "://" in page else manual(page)
    evidence = ["SRC-BASE"]
    if fixtures:
        evidence += ["FIXTURE-DEFINITIONS", "FIXTURE-ORACLE-716"]
    if pattern:
        evidence += ["PHPT-V316"]
    REQUIREMENTS.append({
        "id": id, "parent_id": parent, "stage": stage, "kind": kind,
        "required": True, "applicability": "Required; no exclusion granted.",
        "title": title, "state": state or ("IMPLEMENTED_UNVERIFIED" if spans else "NOT_IMPLEMENTED"),
        "sources": [{"url": url, "role": "Owner decision in current session." if url.startswith("session://") else "Official source; online manual is navigation, pinned source controls version."}],
        "implementation": implementation, "tests": tests, "observations": observations,
        "evidence_refs": evidence, "dependencies": list(dependencies),
        "remaining_work": [remaining or "Decompose into version-specific observable obligations and verify normal, invalid, boundary and interaction cases; examples do not establish whole-feature coverage."]})


# Aggregate rows intentionally overlap their children. They are not a denominator.
DOMAINS = [
    ("LANG", None, "Full PHP 8.5.12 language semantics", "langref", "119-142,640-1988,4898-6163"),
    ("LEX", "LANG", "Tags, lexical grammar, literals and source context", "language.basic-syntax", "10-18,119-142"),
    ("VALUES", "LANG", "Types, values, conversions and resources", "language.types", "2329-2515,2703-3390"),
    ("VARS", "LANG", "Variables, scope, aliases and predefined variables", "language.variables", "2358-2515"),
    ("OPS", "LANG", "Operators, precedence and evaluation order", "language.operators", "919-1060,5404-5500"),
    ("FLOW", "LANG", "Control flow, loading and termination", "language.control-structures", "1615-1836,5501-6138"),
    ("FUN", "LANG", "Functions, call conventions and continuations", "language.functions", "1875-1988,3921-4154"),
    ("OOP", "LANG", "Classes, object model and all interactions", "language.oop5", "1163-1614,3404-3712,5600-5930"),
    ("NAMES", "LANG", "Namespace/name resolution across source units", "language.namespaces", "143-397"),
    ("ERROR", "LANG", "Exceptions, diagnostics, timing and routing", "language.errors", "1996-2167,2226-2250,5517-5599,6150-6163"),
    ("LIB", None, "All built-in functions/classes/constants/streams", "funcref", "4159-4795"),
    ("EXT", None, "Standard extensions and native-extension hosting", "extensions", "4159-4795"),
    ("SAPI", None, "Full CLI and Web execution environments", "features.commandline", "3-6"),
    ("ABI", None, "Existing compiled extension binary compatibility", source("Zend/zend_modules.h"), ""),
    ("ECOSYSTEM", None, "Unmodified PHP applications and dependencies", "language.oop5.autoload", ""),
    ("QUALITY", None, "Reproducible differential and runtime validation", "internals2.tests", ""),
    ("PRESERVE", None, "Preserve ALL language and installed/test contracts", "langref", "1-6"),
]
for id, parent, title, page, spans in DOMAINS:
    add(id, parent, title, page, spans, kind="aggregate", remaining="Aggregate inventory is incomplete. Do not mark VERIFIED from a few passing cases or average child states.")

add("LEX-TAGS", "LEX", "PHP/HTML boundaries and short echo tags", "language.basic-syntax.phptags", "10-18", pattern=r"(php_tag|php_short|inline_html)", remaining="Adapter requires initial <?php and handles only a trailing closing tag; mixed HTML/PHP and short echo tags remain required.")
add("LEX-IDENTIFIERS", "LEX", "Identifier byte grammar and reserved names", source("Zend/zend_language_scanner.l"), "119-142", remaining="Tokenizer identifiers use ASCII A-Z/a-z/_ ranges. Audit non-ASCII identifier bytes and all reserved/case rules against the pinned scanner.")
add("LEX-STRINGS", "LEX", "Binary strings, escapes, interpolation, heredoc/nowdoc", "language.types.string", "413-523,4527-4541", pattern=r"(heredoc|nowdoc|binary_string)", remaining=".NET text representation and text offsets do not establish arbitrary byte-string semantics. Heredoc/nowdoc and invalid UTF-8 cases remain unmapped.")
add("LEX-ATTRIBUTES", "LEX", "Attribute syntax, metadata, validation and Reflection", "language.attributes", "119-133", pattern=r"^Zend/tests/attributes/", state="NOT_IMPLEMENTED", remaining="#[...] is consumed as a # line comment. Matching output in this directory can be accidental; metadata/validation/Reflection are still required.")
add("LEX-MAGIC", "LEX", "All magic constants with exact source/member context", "language.constants.magic", "291-294", fixtures=[("PHP_v3_16_namespaces_oracle_cases.json", "namespaced class name")], remaining="__NAMESPACE__ exists; latest README lists __CLASS__/__FUNCTION__/__METHOD__/__LINE__/__FILE__/__DIR__ absent. Census all PHP 8.5.12 magic constants, including trait/property context.")
add("VALUES-INT", "VALUES", "Int64 literals, conversion, overflow and diagnostics", "language.types.integer", "564-612,2821-2912", fixtures=[("PHP_v3_13_numeric_oracle_cases.json", "literal max|int add overflow|int mul overflow")], remaining="Int64 and overflow-to-double code exists. Verify every cast/operator/boundary and mixed-type diagnostic; obsolete decimal-only gap entries are not current evidence.")
add("VALUES-FLOAT", "VALUES", "Double values, rounding/formatting, INF/NAN and signed zero", "language.types.float", "2703-2820,2834-2924", fixtures=[("PHP_v3_13_numeric_oracle_cases.json", "negative zero|shortest round trip|comparison nan")])
add("VALUES-ARRAY", "VALUES", "Ordered arrays, keys, copies, recursion and references", "language.types.array", "2329-2357,3077-3152", fixtures=[("PHP_v3_13_numeric_oracle_cases.json", "array literal key|array next index|array values")])
add("VALUES-RESOURCES", "VALUES", "Resource identity, type, closure and lifecycle", "language.types.resource", remaining="No PHP resource value/backend lifecycle mapped in current adapter. ALL-only I/O functions do not establish PHP resource semantics.")
add("VALUES-TYPES", "VALUES", "All type positions, unions/intersections/DNF, coercion and variance", "language.types.declarations", "1837-1874,3251-3389", fixtures=[("PHP_v3_13_numeric_oracle_cases.json", "typed int parameter|typed float parameter|union and nullable")], pattern=r"^Zend/tests/type_declarations/")
add("VARS-SCOPE", "VARS", "Variable variables and global/static/local scope/lifetime", "language.variables.scope", "1128-1162,2358-2420,3921-4154", fixtures=[("PHP_v3_7_native_oracle_cases.json", None)])
add("VARS-REFS", "VARS", "All alias/reference targets and effects", "language.references", "2369-2515,4849-4896", fixtures=[("PHP_v3_9_1_ref_return_oracle_cases.json", None)], remaining="Typed/readonly property references are explicitly rejected at 2468-2469 and typed static references at 2488; rejecting PHP-valid cases is incomplete compatibility.")
add("VARS-SUPERGLOBALS", "VARS", "GLOBALS and all CLI/Web/environment superglobals", "language.variables.superglobals", "2373-2396", remaining="Some read-only GLOBALS behavior exists. Request/environment/CLI population and mutable alias/write-through contracts are not established.")
add("OPS-ALL", "OPS", "All operator/value combinations, precedence and order", "language.operators", "919-1060,5404-5500", fixtures=[("PHP_v3_13_numeric_oracle_cases.json", "power right|strict equality|match is strict")])
add("OPS-PIPE85", "OPS", "PHP 8.5 functional pipe operator and callable evaluation", "language.operators.functional", "119-120,970-1060", state="NOT_IMPLEMENTED", remaining="Pinned PHP8.5.12 grammar defines T_PIPE; current tokenizer/precedence table has no dedicated |> operation. Enumerate callable/error/order interactions.")
add("FLOW-BRANCH-LOOP", "FLOW", "Branches/loops/switch/match and nested break/continue", "language.control-structures", "1615-1751,5930-6138", pattern=r"^tests/lang/(break|continue|for|foreach|if|switch|while)")
add("FLOW-ALTERNATIVE", "FLOW", "Colon/end alternative control syntax", "control-structures.alternative-syntax", remaining="No dedicated alternative control syntax mapping found; parser expects conventional statement bodies. Census valid/invalid forms against pinned grammar.")
add("FLOW-DECLARE", "FLOW", "declare directives, strict_types and ticks", "control-structures.declare", "1102-1836", pattern=r"(declare|strict_types)", state="NOT_IMPLEMENTED", remaining="declare is reserved but has no statement/evaluator node. Coercion fixtures do not establish strict_types support.")
add("FLOW-INCLUDE", "FLOW", "include/require/once, paths, scope and load lifecycle", "function.include", "1102-1836", pattern=r"(include|require)", state="NOT_IMPLEMENTED", remaining="Latest README explicitly says include/require absent; no source-load statement mapping. Preserve independent execution and source-unit context.")
add("FLOW-EXIT", "FLOW", "exit/die, statuses, shutdown and unwind behavior", "function.exit", "1102-1836,4159-4795", pattern=r"(exit|die_)", state="NOT_IMPLEMENTED")
add("FLOW-GOTO", "FLOW", "goto/labels and scope/unwind restrictions", "control-structures.goto", "1102-1836", pattern=r"(goto|label)", state="NOT_IMPLEMENTED")
add("FLOW-EVAL", "FLOW", "PHP eval semantics inside independent interpreter", "function.eval", "4159-4795", pattern=r"(eval|assert)", state="NOT_IMPLEMENTED", remaining="Implement PHP eval internally; distinguish the language feature from prohibited forwarding to official php.exe or PowerShell Invoke-Expression.")
add("FUN-PARAMETERS", "FUN", "Arguments/defaults/names/variadics/spread/references", "functions.arguments", "534-563,1875-1952,3921-4154", fixtures=[("PHP_v3_10_typed_oracle_cases.json", None)])
add("FUN-RETURN", "FUN", "Value/reference/typed return and call unwind", "functions.returning-values", "1953-1988,4090-4154,4849-4896", fixtures=[("PHP_v3_9_1_ref_return_oracle_cases.json", None)])
add("FUN-CLOSURES", "FUN", "Closures/arrows/captures/callables and scope rebinding", "functions.anonymous", "640-798,4921-4994", pattern=r"^Zend/tests/closures/", remaining="Partial closure/capture paths exist. Closure::bind/bindTo/call, lifetime and scope contracts remain unmapped/partly unverified.")
add("FUN-GENERATORS", "FUN", "yield/yield from, Generator state/methods and cleanup", "language.generators", "1102-1836,6088-6135", pattern=r"^Zend/tests/generators/", state="NOT_IMPLEMENTED", remaining="No generator continuation/value object mapping. foreach accepts arrays only; all 186 selected generator records are non-PASS.")
add("FUN-FIBERS", "FUN", "Fiber suspension/resumption/state and errors", "language.fibers", pattern=r"^Zend/tests/fibers/", remaining="No Fiber class/runtime mapping; all 111 selected fiber records are non-PASS.")
add("OOP-CLASS", "OOP", "Class/inheritance/construction/visibility and dispatch", "language.oop5", "1301-1614,3495-3655,5740-5925", pattern=r"^tests/classes/")
add("OOP-ANON", "OOP", "Anonymous class scope, creation and identity", "language.oop5.anonymous", "640-918", state="NOT_IMPLEMENTED", remaining="No anonymous-class declaration node mapped. Check all official anonymous-class forms before claiming support.")
add("OOP-PROPERTIES", "OOP", "Typed/promoted/readonly properties and reference constraints", "language.oop5.properties", "1431-1608,2460-2488,3862-3918", fixtures=[("PHP_v3_11_properties_oracle_cases.json", None)], pattern=r"(readonly|property_promotion)")
add("OOP-HOOKS", "OOP", "Property hooks, interfaces and asymmetric visibility", "language.oop5.property-hooks", "1530-1608,3669-3712,3730-3918", fixtures=[("PHP_v3_12_hooks_oracle_cases.json", None)], pattern=r"^Zend/tests/property_hooks/", remaining="23 local hook fixtures are not full coverage. Official selected results retain 163 ALL_ERROR and 31 OUTPUT_DIFF; enumerate all contracts and visibility interactions.")
add("OOP-CONTRACTS", "OOP", "Interfaces/abstract/final and complete signature/property variance", "language.oop5.interfaces", "1163-1226,3540-3570,5891-5925", fixtures=[("PHP_v3_9_2_active_guards.json", "interface|signature|required args")], remaining="Signature helper checks byref/static/count/visibility, but complete parameter/return type variance and property contracts are not established.")
add("OOP-TRAITS", "OOP", "Trait composition, adaptations and all conflicts", "language.oop5.traits", "1340-1430,3404-3494", fixtures=[("PHP_v3_7_trait_oracle_cases.json", None)], pattern=r"^Zend/tests/traits/")
add("OOP-ENUMS", "OOP", "Enum identity, backed values and all contracts", "language.enumerations", "1227-1300,5612-5677", pattern=r"^Zend/tests/enum/")
add("OOP-MAGIC", "OOP", "All magic methods and call ordering/validation", "language.oop5.magic", "3730-3918,4797-4818", pattern=r"^Zend/tests/magic_methods/")
add("OOP-LIFETIME", "OOP", "Object IDs, clone/destruction, GC and weak references", "language.oop5.decon", "2168-2172,4921-4994", pattern=r"(gc_|weakrefs|weakmap|destruct|clone)", remaining="Latest README records no object-ID reuse. PHP lifetime/GC/weak references are not provided merely by allocating .NET objects.")
add("OOP-LAZY", "OOP", "Lazy objects and Reflection lifecycle", "language.oop5.lazy-objects", pattern=r"^Zend/tests/lazy_objects/", remaining="ReflectionClass/lazy-object runtime not mapped; all 229 selected lazy-object records are ALL_ERROR.")
add("OOP-ITERATION", "OOP", "Traversable/Iterator/IteratorAggregate/ArrayAccess protocols", "language.oop5.iterations", "6088-6093", state="NOT_IMPLEMENTED", remaining="foreach currently rejects non-arrays. Array iteration fixtures do not establish object iteration support.")
add("NAMES-STATIC", "NAMES", "Declarations/imports/aliases and static name resolution", "language.namespaces", "143-397", fixtures=[("PHP_v3_16_namespaces_oracle_cases.json", "group use|use with alias|fully qualified names")], pattern=r"^Zend/tests/namespaces/", remaining="Token prepass is partial; README records missing alias/declaration collision and mixed-style/placement checks.")
add("NAMES-DYNAMIC", "NAMES", "Runtime namespace fallback and dynamic/multiple source units", "language.namespaces.fallback", "158-397", fixtures=[("PHP_v3_16_namespaces_oracle_cases.json", "fallback|define and constant")], remaining="v3.16 README explicitly records incorrect dynamic/conditional definition fallback and missing cross-file resolution. Root v3.17 work must be recorded as a later overlay, not this baseline.", dependencies=["FLOW-INCLUDE"])
add("NAMES-AUTOLOAD", "NAMES", "Autoload registration/invocation and class_alias", "language.oop5.autoload", "3233-3250,4159-4795", pattern=r"(autoload|class_alias)", state="NOT_IMPLEMENTED", remaining="No spl_autoload_register/class_alias handlers mapped; autoload_001 records undefined spl_autoload_register.", dependencies=["FLOW-INCLUDE"])
add("ERROR-THROWABLE", "ERROR", "Throwable hierarchy, try/catch/finally and exact context", "language.exceptions", "1770-1811,1996-2167,5517-5599", fixtures=[("PHP_v3_14_exceptions_oracle_cases.json", "finally|catch Throwable|exception from nested")], pattern=r"^Zend/tests/exceptions/")
add("ERROR-DIAGNOSTICS", "ERROR", "Warnings/deprecations/fatals, handlers/suppression/channels", "language.errors", "2226-2250,4601-4661,6158-6162", fixtures=[("PHP_v3_15_diagnostics_oracle_cases.json", "undefined variable|silence operator|trigger_error")], remaining="Optional PHP-format diagnostics use Console.Out. README records omitted diagnostics, E_USER_ERROR nontermination and incorrect @ error_reporting behavior.")
add("LIB-STRINGS", "LIB", "Complete string API and binary offsets/overloads", "ref.strings", "4222-4236,4497-4569", fixtures=[("PHP_v3_13_numeric_oracle_cases.json", "multibyte length")], remaining="strpos/substr use .NET text indexing and several functions have restricted arities. Enumerate all pinned signatures and byte-level obligations.")
add("LIB-ARRAYS", "LIB", "Complete array API including callbacks/references/mutation", "ref.array", "4216-4220,4247-4480", fixtures=[("PHP_v3_13_numeric_oracle_cases.json", "array_keys|array next|array values")])
add("LIB-NUMERIC", "LIB", "Complete numeric/math API, types and errors", "ref.math", "4238-4246,4741-4785", fixtures=[("PHP_v3_13_numeric_oracle_cases.json", "math functions|intdiv and fdiv")])
add("LIB-INTROSPECTION", "LIB", "Reflection, introspection, serialization and display", "ref.classobj", "4671-4674,4687-4739", remaining="function_exists only checks user-function table though built-ins have another dispatcher. Complete Reflection/serialization/introspection remain unmapped.")
add("LIB-STREAMS", "LIB", "Files/streams/resources/wrappers/contexts/filters and binary I/O", "book.stream", "4159-4795", state="NOT_IMPLEMENTED", remaining="No PHP stream/resource backend mapped. Existing ALL-only I/O/HTTP/SQLite features are different interfaces.")
add("LIB-INI", "LIB", "INI discovery/defaults/mutability and all directive effects", "configuration", "4606-4620", fixtures=[("PHP_v3_15_diagnostics_oracle_cases.json", "ini_set")], remaining="README says most INI values are stored without affecting execution, including precision. PHPT worker ignores --INI--.")
add("LIB-SHUTDOWN", "LIB", "Shutdown callbacks/output buffering and cleanup", "function.register-shutdown-function", "4159-4795", state="NOT_IMPLEMENTED", remaining="register_shutdown_function/ob_start are reported undefined; map termination, request and callback ordering together.")

# Retrieved from official php-8.5.12 ext/ tree, including support/dependency dirs.
EXT_DIRS = "bcmath bz2 calendar com_dotnet ctype curl date dba dl_test dom enchant exif ffi fileinfo filter ftp gd gettext gmp hash iconv imap intl json ldap lexbor libxml mbstring mysqli mysqlnd odbc opcache openssl pcntl pcre pdo pdo_dblib pdo_firebird pdo_mysql pdo_odbc pdo_pgsql pdo_sqlite pgsql phar posix random readline reflection session shmop simplexml skeleton snmp soap sockets sodium spl sqlite3 standard sysvmsg sysvsem sysvshm tidy tokenizer uri xml xmlreader xmlwriter xsl zend_test zip zlib".split()
for name in EXT_DIRS:
    spans = {"json": "2558-2702,4169-4215", "standard": "4159-4795", "spl": "2021-2034"}.get(name, "")
    add("EXT-" + name.upper().replace("_", "-"), "EXT", "PHP 8.5.12 ext/" + name + " public surface and behavior", source("ext/" + name, True), spans, kind="aggregate", remaining="Enumerate public functions/classes/constants/INI, dependencies and PHPT. Source-directory count is not an API denominator. Record platform applicability without silently excluding required behavior.")
    REQUIREMENTS[-1]["extension_directory"] = name
    REQUIREMENTS[-1]["classification"] = (
        "development/test support; record disposition" if name in ["dl_test", "skeleton", "zend_test"] else
        "bundled dependency/internal component; exposed behavior needs census" if name in ["lexbor", "mysqlnd"] else
        "API/extension family; public surface and platform applicability incomplete")

add("SAPI-CLI", "SAPI", "Complete CLI flags/files/stdin/argv/env/channels/statuses", "features.commandline", "3-6", remaining="Code-string adapter exists; full CLI executable contract is not implemented/verified as one interface.")
add("SAPI-WEB", "SAPI", "Web requests/responses/headers/cookies/sessions/uploads/lifecycle", source("main/SAPI.h"), remaining="No PHP Web SAPI implementation mapped. Existing ALL HTTP server is not PHP SAPI behavior.")
add("SAPI-HOSTS", "SAPI", "Built-in server/CGI/FastCGI/Apache and LinuxFPM hosting", source("sapi", True), state="BLOCKED", remaining="Owner approved built-in server, CGI/FastCGI, Apache module and Linux FPM on Windows11x64/Linuxx64. Concrete host configurations and executable test environments remain unavailable/unverified; no renewed scope approval is needed.", dependencies=["DEP-WEB-PLATFORM"])
add("ABI-LOADER", "ABI", "Load existing binary extensions and validate dependencies/exports/builds", source("ext/standard/dl.c"), remaining="No independent Zend extension loader mapped. dl.c checks zend_api/build_id; loading a DLL or forwarding to official PHP is insufficient.", dependencies=["DEP-ABI-ARCH"])
add("ABI-MODULE", "ABI", "Module layout/globals and startup/shutdown/request lifecycle", source("Zend/zend_modules.h"), remaining="Pinned header defines ZEND_MODULE_API_NO=20250925, size/API/debug/ZTS/build ID and callbacks. Implement/test actual layout, exports and lifecycle.", dependencies=["DEP-ABI-ARCH"])
add("ABI-VALUES", "ABI", "Native zval/string/HashTable/object/resource layout and ownership", source("Zend/zend_types.h"), "2329-2515", state="NOT_IMPLEMENTED", remaining="PowerShell value/refcell objects are not Zend binary layouts. Inventory native imports/exports, ownership/refcount/callback/unwinding contracts.", dependencies=["DEP-ABI-ARCH"])
add("ABI-CORPUS", "ABI", "Unmodified standard and third-party extension binary corpus", source("Zend/zend_API.c"), remaining="Binary compatibility is required. Inventory available binary build tuples/dependencies and test unmodified loads/API/lifecycle/crashes.", dependencies=["DEP-ABI-CORPUS"])
add("ABI-ARCH-DECISION", "ABI", "Implement and validate owner-approved native-ABI Design A", source("Zend/zend_modules.h"), state="IMPLEMENTED_UNVERIFIED", kind="control", remaining="Owner approved DesignA in docs/design/PHP_NATIVE_ABI_DESIGN.md, including isolated native layer and value/call boundary work with fixed SDK definitions and existing compiler. Prototype/runtime evidence remains to be produced. Broader DesignB/source adoption/new dependencies are not implicitly approved.", dependencies=["DEP-ABI-ARCH"])
REQUIREMENTS[-1]["evidence_refs"] = ["OWNER-DECISIONS-20261112"]
add("ECOSYSTEM-COMPOSER", "ECOSYSTEM", "Composer/autoload and unchanged dependency packages", "language.oop5.autoload", remaining="No unchanged Composer application evidence in mapped reports. Record locked versions, dependencies and actual behaviors.", dependencies=["FLOW-INCLUDE", "NAMES-AUTOLOAD"])
add("ECOSYSTEM-APPS", "ECOSYSTEM", "Unmodified real CLI/Web apps and persistent/error behavior", "features", remaining="Real-app corpus and acceptance behaviors remain unmapped; do not replace with toy examples.")
add("QUALITY-FIXTURE", "QUALITY", "Preserve fixture contracts and distinguish refusal guards", source("run-tests.php"), "1-6", kind="control", remaining="940 defined checks include refusal guards and parity examples. Historical oracle audit of716 found3 ALL_REJECTS_VALID_PHP and2 MATCH_BUT_PHP_DIAGNOSTIC. This audit does not rerun runtime tests.")
REQUIREMENTS[-1]["evidence_refs"] = ["FIXTURE-DEFINITIONS", "FIXTURE-ORACLE-716"]
add("QUALITY-PHPT", "QUALITY", "Full applicable PHPT including configuration/setup/cleanup", source("run-tests.php"), state="IMPLEMENTED_UNVERIFIED", kind="control", remaining="Worker only checks normalized Console.Out; ignores INI/CLEAN/module setup and cannot inject request/stdin/argv/env sections.")
REQUIREMENTS[-1]["implementation"] = [{"path": "tools/phpt/PhptWorker.ps1", "start_line": 29, "end_line": 156, "baseline_commit": BASE}]
REQUIREMENTS[-1]["evidence_refs"] = ["PHPT-V316", "PHPT-HARNESS"]
add("QUALITY-STRICT", "QUALITY", "Separate raw byte channels/status and observable side effects", source("run-tests.php"), state="IMPLEMENTED_UNVERIFIED", kind="control", remaining="New strict comparator has14 bounded probes:5PASS/9DIFFERENT. Full side effects/SAPI/ABI/INI/input coverage is not established.")
REQUIREMENTS[-1]["implementation"] = [{"path": "tools/differential/evaluate.py", "location_status": "new worktree tooling outside baseline; inspect report separately"}]
REQUIREMENTS[-1]["evidence_refs"] = ["STRICT-14-NEW"]
add("QUALITY-LIMITS", "QUALITY", "Execution/memory/stack/configuration limits and stability", "ini.core", "5501-5504", kind="control", remaining="Unconditional100000-statement limit differs from configurable PHP runtime limits. Historical43TIMEOUT/1CRASH/2MEMORY outcomes unresolved.")
add("QUALITY-PLATFORMS", "QUALITY", "Windows11x64 and Linuxx64 build/runtime evidence", source("Zend/zend_build.h"), state="BLOCKED", kind="control", remaining="Both OS/CPU targets are approved. Current reference evidence is Windows x64/ZTS; actual Linux distribution/reference/build/test environment and binary tuples remain unavailable/unverified. Windows compilation is never Linux runtime validation.", dependencies=["DEP-WEB-PLATFORM", "DEP-ABI-CORPUS"])
add("PRESERVE-ALL", "PRESERVE", "Retain ALL original syntax/features and independent execution", "langref", "1-6", kind="control", remaining="Shared-runtime changes require isolated existing ALL regression. Preserve installed files and unrelated functionality.")
add("PRESERVE-NO-FORWARD", "PRESERVE", "Official PHP remains oracle only; candidate executes independently", source("Zend/zend_execute.c"), "9-9,640-1988,4898-6163", kind="control", remaining="Own parser/evaluator visible; preserve transitive no-forwarding audit and execution evidence as ABI bridges/loaders are added.")
add("STAGE2-ALL-POWER", None, "ALL itself reaches PHP-equivalent functional power", "session://user-decision/2026-11-12", kind="aggregate", stage=2, remaining="Approved next stage after Stage1; not decomposed, implemented or measured by this audit.")
add("STAGE2-INTEROP", None, "PHP/ALL bidirectional calls and shared data", "session://user-decision/2026-11-12", kind="aggregate", stage=2, remaining="Approved next stage. Define call/type/identity/ownership/ref/exception/reentrancy contracts; not current shared semantics.")

ORACLE = json.loads(text("reports/FIXTURE_ORACLE_PHP_8.5.12.json"))
COUNTS = Counter({k: 0 for k in ["NOT_IMPLEMENTED", "IMPLEMENTED_UNVERIFIED", "VERIFIED", "BLOCKED"]})
COUNTS.update(x["state"] for x in REQUIREMENTS)
GAPS = [
    ("LANGUAGE", "All grammar/semantic/invalid/boundary/interaction leaf obligations not enumerated."),
    ("LIBRARY", "Complete public functions/classes/methods/constants/INI/signature census missing."),
    ("EXTENSIONS", "72 source directories catalogued; public API/platform/native-dependency census incomplete."),
    ("NATIVE-BINARIES", "Existing binary build tuples, imports/exports/dependencies and accepted corpus missing."),
    ("SAPI", "Full CLI/Web host/protocol/environment/request lifecycle map incomplete."),
    ("PHPT", "Only selected historical three-directory core subset measured; full pack/extension/host setups missing."),
    ("EVIDENCE", "Full separate raw channels/status/side-effects/configuration/lifecycle conformance missing."),
    ("REAL-APPS", "Unmodified Composer/framework/application corpus and acceptance behavior missing."),
]
MANIFEST = {
    "schema_version": "1.0-initial", "status": "NOT_COMPLETE", "exhaustive": False,
    "completion_percentage": None, "audit_date": "2026-11-12",
    "audit_baseline": {"commit": BASE, "adapter_path": ADAPTER, "adapter_sha256": sha(ADAPTER),
                       "adapter_development_version": "3.16", "runtime_execution_performed_by_this_audit": False},
    "target": {"php_version": "8.5.12", "stage1": {"language": True, "cli": True, "web": True,
                "standard_extensions": True, "existing_native_extension_binaries": True},
               "stage2": {"all_php_equivalent_functional_power": True,
                           "bidirectional_php_all_calls_and_shared_data": True, "sequence": "after stage1"},
               "reference_environment": "Windows11/Windows PowerShell5.1; PHP8.5.12 ZTS VC2022 x64 oracle",
               "platforms": ["Windows11x64", "Linuxx64"],
               "web_sapis": ["built-in Web server", "CGI", "FastCGI", "Apache module", "FPM on Linux"],
               "native_abi_design": "DesignA approved: isolated ALL-owned native ABI layer and reviewed value/call boundary integration; not stock runtime forwarding",
               "scope_authority": "Owner decisions2026-11-12; docs/COMPAT_TARGET.md. Historical CLI subset is not scope exclusion."},
    "state_definitions": {
        "NOT_IMPLEMENTED": "No implementing path mapped or current source/docs explicitly reject/ignore behavior; not an exhaustive proof over repository text.",
        "IMPLEMENTED_UNVERIFIED": "Implementation/limited test path exists, full stated scope lacks accepted verification.",
        "VERIFIED": "Precisely bounded full obligation with accepted reproducible evidence; aggregate PASS counts insufficient. No initial rows use this state.",
        "BLOCKED": "Concrete unresolved design/environment/build-tuple dependency for this row; not all project work blocked."},
    "counting_policy": {"requirements_row_count": len(REQUIREMENTS), "row_counts_by_state": dict(COUNTS),
        "counts_are_feature_denominator": False, "aggregate_and_leaf_rows_may_overlap": True,
        "completion_gate": "Fail closed while exhaustive=false, inventory gaps/required decisions remain, or required applicable Stage1 obligations lack accepted full-scope VERIFIED evidence. Stage2 tracked independently and remains in final objective."},
    "official_source_snapshot": {"repository": "php/php-src", "tag": "php-8.5.12", "read_date": "2026-11-12",
        "read_files": ["Zend/zend_language_parser.y", "Zend/zend_language_scanner.l", "Zend/zend_modules.h",
            "Zend/zend_types.h", "Zend/zend_API.c", "Zend/zend_closures.c", "Zend/zend_generators.c",
            "Zend/zend_fibers.c", "Zend/zend_attributes.c", "main/SAPI.h", "ext/standard/dl.c",
            "ext/standard/basic_functions.stub.php", "UPGRADING"],
        "manual_policy": "Online manual is not frozen. Reconcile leaves with pinned8.5.12 source/signatures/PHPT.",
        "extension_source_directories": EXT_DIRS, "directory_count_is_api_denominator": False},
    "inventory_gaps": [{"id": "INV-" + k, "description": v, "required_before_exhaustive": True} for k, v in GAPS],
    "dependencies": [
        {"id": "DEP-ABI-ARCH", "state": "approved", "description": "Owner approved DesignA plus fixed SDK types/existing compiler and necessary isolated value/call integration. Broader DesignB/additional dependencies remain separate."},
        {"id": "DEP-WEB-PLATFORM", "state": "environment_pending", "description": "Windows11x64/Linuxx64 and built-in server/CGI/FastCGI/Apache/LinuxFPM scope approved. Concrete executable hosting/test environments remain unresolved."},
        {"id": "DEP-ABI-CORPUS", "state": "inventory_pending", "description": "Inventory available existing binaries and dependencies/build tuples; no compatibility result assumed."}],
    "evidence_catalog": [
        {"id": "OWNER-DECISIONS-20261112", "kind": "owner_decision", "path": "docs/COMPAT_TARGET.md", "quality": "Current-session explicit approval: DesignA, Windows11x64/Linuxx64, full listed Web SAPI. Approval is not runtime verification."},
        {"id": "SRC-BASE", "kind": "source_inspection", "path": ADAPTER, "commit": BASE, "sha256": sha(ADAPTER), "quality": "Static mapping; not runtime/conformance proof."},
        {"id": "FIXTURE-DEFINITIONS", "kind": "test_definition", "path": "package/ALL_PHP_v3_16_test.ps1", "commit": BASE,
         "quality": "940 defined checks including guards/17parity examples; not complete feature denominator.", "limitations": ["Audit did not rerun them.", "Earlier oracle versions occur in historical collections."]},
        {"id": "FIXTURE-ORACLE-716", "kind": "historical_oracle_report", "path": "reports/FIXTURE_ORACLE_PHP_8.5.12.json", "commit": BASE,
         "case_count": ORACLE["total"], "summary": ORACLE["summary"], "quality": "Official PHP audit of716 earlier definitions; not candidatev3.16 execution."},
        {"id": "PHPT-V316", "kind": "historical_selected_phpt_output_report", "path": PHPT, "commit": BASE, "sha256": sha(PHPT),
         "case_count": len(PHPT_ROWS), "verdict_counts": dict(Counter(x["verdict"] for x in PHPT_ROWS)),
         "quality": "Normalized Console.Out only; selected core oracle-PASS cases.",
         "limitations": ["Not rerun by audit.", "154other oracle outcomes excluded from historical subset, not approved requirement exclusions.",
            "Separate stderr/status/side effects/INI/CLEAN/module lifecycle not checked.", "Attribute comments can cause accidental PASS.",
            "Extensions/Web/native ABI not measured.", "Three-worker time/crash results can vary."]},
        {"id": "PHPT-HARNESS", "kind": "source_inspection", "path": "tools/phpt/PhptWorker.ps1", "commit": BASE, "quality": "Read section filtering/Normalize/verdict code."},
        {"id": "STRICT-14-NEW", "kind": "worktree_strict_differential_report", "path": "reports/strict-differential-20261112-initial/report.json",
         "quality": "Root reports14bounded probes:5PASS/9DIFFERENT, separate raw stdout/stderr and status. Outside pinned baseline; not full feature coverage.",
         "limitations": ["This audit did not rerun probes.", "Does not prove all side effects/SAPI/ABI/inputs/INI."]}],
    "requirements": REQUIREMENTS}


def build_markdown():
    verdicts = Counter(x["verdict"] for x in PHPT_ROWS)
    result = "\n".join(f"| {k} | {v:,} |" for k, v in verdicts.items())
    states = "\n".join(f"| `{k}` | {COUNTS[k]} |" for k in ["NOT_IMPLEMENTED", "IMPLEMENTED_UNVERIFIED", "VERIFIED", "BLOCKED"])
    groups = []
    for name in ["generators", "fibers", "lazy_objects", "attributes", "namespaces", "property_hooks", "type_declarations", "traits", "enum", "closures"]:
        subset = [x for x in PHPT_ROWS if x["test"].replace("\\", "/").startswith("Zend/tests/" + name + "/")]
        c = Counter(x["verdict"] for x in subset)
        other = ", ".join(k + "=" + str(v) for k, v in c.items() if k != "PASS")
        groups.append(f"| `{name}` | {len(subset)} | {c['PASS']} | {other} |")
    return f"""# PHP 要件・証拠の初回監査

更新日：2026-11-12。**NOT_COMPLETE / exhaustive=false**。
[機械可読表](PHP_REQUIREMENTS_MATRIX.json)は初回棚卸しで、全機能の分母ではない。集約行とleafは重なり、行数・実装行数・テスト合格数を完全互換率へ換算しない。

## 対象と監査境界

所有者が決めたStage1は **PHP8.5.12の完全互換**。言語、CLI、Web、標準拡張、**既存のコンパイル済みネイティブ拡張バイナリ**を含む。OS/CPUはWindows11x64とLinuxx64、Webは内蔵サーバー・CGI/FastCGI・Apacheモジュール・LinuxFPM。案Aの独立ネイティブABI基盤実装と必要な値/呼出し境界変更も承認済み。承認と実行検証は別扱い。
Stage2のALL自身のPHP相当の機能力、PHP/ALL双方向呼出し・データ共有も目標に残し、Stage1の後に扱う。

監査基準：`{BASE}`。開発版はv3.16だがファイル名は`{ADAPTER}`のまま。
実装SHA-256：`{sha(ADAPTER)}`。行参照はこのコミットのもので、将来の編集後の現在位置ではない。

この監査はソース・テスト定義・既存レポートの読み取りと再集計を行い、**PHP/ALLコード、回帰、PHPTを実行していない**。公式ソーステキストを参照したが、オラクルのバイナリを再ダウンロードしていない。

rootが追加した厳密差分14プローブの結果は5PASS/9DIFFERENTと報告されている。`reports/strict-differential-20261112-initial/report.json`は別証拠で、旧PHPTの観測条件と混ぜない。rootの940/940回帰結果や今後のv3.17改修も、基準を書き換えず別の証拠として追記する。

## 状態の扱い

| 状態 | 管理行数 |
|---|---:|
{states}

これは管理行数で進捗率ではない。`aggregate`は未分解の領域、`leaf`は具体化した義務、`control`は検証・保護・判断条件。初回VERIFIED=0は「動く機能0」ではなく、登録義務の全範囲に十分な証拠をまだ対応付けていないという意味。
BLOCKEDはその行の具体的な設計・環境・build組合せ依存を示し、独立した調査や比較器改善まで停止する意味ではない。

## 既存テストの証拠

v3.16入口は940チェックを定義する。正常出力のほか拒否を確認する`error_contains`ガード、歴史的PHP/ALL対比17件を含む。940はPHP正常系全機能の分母ではない。

`FIXTURE_ORACLE_PHP_8.5.12.json`は以前の716定義の**公式PHP側**の記録：MATCH642、ERROR_AGREES69、ALL_REJECTS_VALID_PHP3、MATCH_BUT_PHP_DIAGNOSTIC2。v3.16候補自体の新しい実行結果ではなく、716件全ての厳密互換証明でもない。

既存`PHPT_CORE_ALL_v3_16.jsonl`を再集計し、既存Markdownと一致した。

| 記録判定 | 件数 |
|---|---:|
{result}
| 合計 | {len(PHPT_ROWS):,} |

5,819は3領域（Zend/tests、tests/lang、tests/classes）から、当時のWindows公式PHP自身がPASSしたものだけ。元5,973件からSKIP148/WARN3/FAIL1/XFAIL1/ORACLE_ABORT1を除いた計測集合。154件を最終要件から除外する決裁ではない。ext全体/Web/ABI/実アプリは未計測。

次は厳密なフォルダー接頭辞での再集計で、新規実行ではない。

| Zend/tests/下 | 件数 | PASS | その他 |
|---|---:|---:|---|
{chr(10).join(groups)}

`PhptWorker.ps1`はConsole.Out文字列を取り、改行・前後空白を正規化してEXPECT系と比較する。**独立stderr・終了コード・任意バイト・副作用の一致ではない**。INI/CLEAN/module設定は再現せず、stdin/argv/env/request/header等の入力セクションを入口制約で実行できない。属性をコメントとして捨てても出力が偶然一致しうるため、属性16PASSを機能実装証拠にしない。

3並列、1本30秒、メモリ上限という条件で、非再現CRASH/時間切れ/MEMORYが記録され、根因は未確定。

## ソースで確認した主要な残件

| 領域 | 基準ソース・記録上の事実 |
|---|---|
| Generator/Fiber | 継続処理の実装を特定できない。foreachはarrayのみ（6088–6093行）。対象186/111件にPASSなし |
| include/require | 最新READMEが未実装と明記。parserにロード経路なし |
| 属性 | tokenizerの#コメント処理（119–133行）が#[...]を消費 |
| 名前空間 | 143–397行の事前トークン変換。動的定義/別ファイル/衝突チェック等の制約 |
| 型付き参照 | property/staticへの参照を2468–2469/2488行で明示拒否 |
| strict_types | declareは予約語のみ、文・実行ノードなし |
| バイナリ文字列 | .NET文字列。strpos/substrも文字単位のAPI |
| 終了/診断/設定 | exit経路なし。診断は任意モードConsole.Out。INIは主に値保持のみ |
| 実行上限 | 5501–5504行で100,000文を超えると一律停止 |
| Web/ABI | PHP SAPI、独立Zend loader/export/layout/lifecycleの実装証拠なし |

古い「decimal中心」「try/catch/namespace未実装」を現在の不足として転記しない。v3.13はint64/double、v3.14は例外、v3.16は名前空間を**部分実装**した。rootの後続v3.17修正はこの基準の後に対応付ける。

## 公式ソースと残る棚卸し

[php-8.5.12公式ソース](https://github.com/php/php-src/tree/php-8.5.12)の文法/字句、closure/generator/fiber/attributes、Zend API/型/module、SAPI、拡張loader、標準stub、UPGRADINGを参照。[言語参照](https://www.php.net/manual/en/langref.php)・[関数参照](https://www.php.net/manual/en/funcref.php)は更新されるため、正確な版は固定ソースへ照合する。

ext/公式ディレクトリ72件を登録したが、zend_test/dl_test/skeletonは試験支援、lexbor/mysqlnd等は依存/内部機構を含み、「公開拡張API72個」とは扱わない。全関数/クラス/定数/INI/依存/PHPTとOS/build適用性のleaf棚卸しが必要。JSON/standard/SPLの一部コードが存在しても全API達成ではない。

[`zend_modules.h`](https://github.com/php/php-src/blob/php-8.5.12/Zend/zend_modules.h)はAPI番号20250925、size/API/debug/ZTS/build ID、module/request globalsとstartup/shutdownを定義。[`dl.c`](https://github.com/php/php-src/blob/php-8.5.12/ext/standard/dl.c)はAPI/build IDを照合。ABIは同名関数だけではなく、[値のlayout](https://github.com/php/php-src/blob/php-8.5.12/Zend/zend_types.h)、所有権/refcount、exports、呼出し規約、callbacks、寿命まで実バイナリで照合する必要がある。

`inventory_gaps`に全言語leaf、全API、native binary、SAPI、PHPT、観測器、実アプリの未棚卸しを登録。これらが残る間はexhaustive=trueにしない。**案A、Windows11x64/Linuxx64、内蔵Web/CGI/FastCGI/Apache/LinuxFPMは承認済み**。残るのは実行環境・具体的なホスト構成・既存バイナリ検証corpusなど。案Bや追加依存の採用は別途判断する。未確定を理由に目標を縮小したり、済んだ決裁を再要求したりしない。

完了ゲートは棚卸し・必要判断・各必須義務の受入れ可能なVERIFIED証拠・既存ALL/PHP回帰・差分/PHPT/CLI/Web/実アプリ/実binary試験・再現ログ/hash/rollback・所有者最終受入れが揃うまで失敗させる。管理行数を完成根拠にしない。
"""


if __name__ == "__main__":
    (ROOT / "docs/PHP_REQUIREMENTS_MATRIX.json").write_text(json.dumps(MANIFEST, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (ROOT / "docs/PHP_REQUIREMENTS_COVERAGE.md").write_text(build_markdown(), encoding="utf-8")
    print(json.dumps({"status": MANIFEST["status"], "exhaustive": False, "rows": len(REQUIREMENTS), "states": dict(COUNTS), "base": BASE, "adapter_sha256": sha(ADAPTER)}))
