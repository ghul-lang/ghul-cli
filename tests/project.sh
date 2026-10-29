#!/usr/bin/env bash
# End-to-end test of building and running a project described by a
# ghul-project.json, driving the built CLI as an installed tool would run,
# under a scratch HOME so the compiler is installed on demand.
#
# The wasm checks build with the runtime library, which carries the core
# sources, fetched from Git
# and run the program under Node.js.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
config="$repo_root/ghul-test.json"
trap 'rm -rf "$scratch" "$config"' EXIT

dotnet build -nologo -c Debug "$repo_root/cli/ghul-cli.ghulproj" -o "$scratch/build" >&2
cli="$scratch/build/ghul-cli.dll"

# The local tools, ghul-test among them, are found in the packages folder
# under the real HOME, which the scratch HOME would otherwise hide; the
# tool cache under the scratch HOME is rebuilt from it before they run.
export NUGET_PACKAGES="${NUGET_PACKAGES:-$HOME/.nuget/packages}"
export HOME="$scratch/home"
export XDG_CACHE_HOME="$scratch/cache"
mkdir -p "$HOME"

fail() {
    echo "project: $1" >&2
    exit 1
}

check() {
    local got="$1" want="$2" label="$3"
    [[ "$got" == "$want" ]] || fail "$label: expected '$want', got '$got'"
}

# A program in two files, so the build has to find both through the globs.
program="$scratch/greeter"
mkdir -p "$program/src"
cat > "$program/ghul-project.json" <<'JSON'
{
    // a comment and a trailing comma, both of which a manifest may carry
    "name": "greeter",
    "targets": ["wasm"],
    "dependencies": { "ghul-runtime": { "version": ">=0.0.0" } },
}
JSON
cat > "$program/src/main.ghul" <<'GHUL'
namespace Greeter is
    use IO.Std.write_line

    entry(args: string[]) is
        write_line(greeting(if args.count > 0 then args[0] else "world" fi))
    si
si
GHUL
cat > "$program/src/greeting.ghul" <<'GHUL'
namespace Greeter is
    greeting(name: string) -> string => "hello, {name}"
si
GHUL

echo "project: a two-file program builds..." >&2
(cd "$program" && dotnet "$cli" build) >&2 || fail "ghul build failed"
[[ -f "$program/out/wasm/greeter.wasm" ]] || fail "expected out/wasm/greeter.wasm"
[[ -f "$program/out/wasm/greeter.mjs" ]] || fail "expected the greeter.mjs loader beside the build"

echo "project: 'ghul run <script>' still runs the script, beside a manifest..." >&2
cat > "$program/script.ghul" <<'GHUL'
entry() is
    IO.Std.write_line("the script, not the project")
si
GHUL
out="$(cd "$program" && dotnet "$cli" run script.ghul 2>/dev/null)"
check "$out" "the script, not the project" "ghul run <script> output"

echo "project: a library builds..." >&2
library="$scratch/shapes"
mkdir -p "$library/src"
cat > "$library/ghul-project.json" <<'JSON'
{ "name": "shapes", "kind": "library", "dependencies": { "ghul-runtime": { "version": ">=0.0.0" } } }
JSON
cat > "$library/src/shapes.ghul" <<'GHUL'
namespace Shapes is
    area(width: int, height: int) -> int => width * height
si
GHUL
# A wasm library is compiled into a program from source; built on its own
# it is only checked, and writes nothing.
(cd "$library" && dotnet "$cli" build) >&2 || fail "ghul build of a library failed"

echo "project: a library is not run..." >&2
if err="$(cd "$library" && dotnet "$cli" run 2>&1 >/dev/null)"; then
    fail "expected ghul run of a library to fail"
fi
[[ "$err" == *"ghul: shapes is a library, which cannot be run"* ]] || fail "unexpected message for running a library: $err"

echo "project: a manifest with a problem fails with the problem..." >&2
broken="$scratch/broken"
mkdir -p "$broken/src"
cat > "$broken/ghul-project.json" <<'JSON'
{ "name": "Broken Name" }
JSON
if err="$(cd "$broken" && dotnet "$cli" build 2>&1)"; then
    fail "expected a manifest with a bad name to fail"
fi
[[ "$err" == *"ghul: ghul-project.json: name:"* ]] || fail "unexpected message for a bad manifest: $err"

echo "project: a manifest listing dotnet is refused..." >&2
dotnet_manifest="$scratch/dotnet-manifest"
mkdir -p "$dotnet_manifest/src"
cat > "$dotnet_manifest/ghul-project.json" <<'JSON'
{ "name": "dotnet-manifest", "targets": ["dotnet"] }
JSON
if err="$(cd "$dotnet_manifest" && dotnet "$cli" build 2>&1)"; then
    fail "expected a manifest listing dotnet to fail"
fi
[[ "$err" == *"ghul does not build for dotnet"* ]] || fail "unexpected message for a dotnet manifest: $err"

echo "project: --target dotnet is refused..." >&2
if err="$(cd "$program" && dotnet "$cli" build --target dotnet 2>&1)"; then
    fail "expected --target dotnet to fail"
fi
[[ "$err" == *"ghul does not build for dotnet"* ]] || fail "unexpected message for --target dotnet: $err"
if err="$(cd "$scratch" && dotnet "$cli" new refused --target dotnet 2>&1)"; then
    fail "expected ghul new --target dotnet to fail"
fi
[[ "$err" == *"ghul does not build for dotnet"* ]] || fail "unexpected message from ghul new --target dotnet: $err"

echo "project: a target the manifest does not list is refused..." >&2
if err="$(cd "$program" && dotnet "$cli" build --target llvm 2>&1)"; then
    fail "expected an unlisted target to fail"
fi
[[ "$err" == *"ghul: the manifest does not list the target llvm; it lists wasm"* ]] || fail "unexpected message for an unlisted target: $err"

echo "project: 'ghul build' with no manifest fails..." >&2
empty="$scratch/empty"
mkdir -p "$empty"
if err="$(cd "$empty" && dotnet "$cli" build 2>&1)"; then
    fail "expected ghul build with no manifest to fail"
fi
[[ "$err" == *"ghul: no ghul-project.json in $empty"* ]] || fail "unexpected message for no manifest: $err"

echo "project: the editor files round-trip through the compiler ghul names..." >&2
response_file="$scratch/editor.rsp"
globs_file="$scratch/editor.globs"
(cd "$program" && dotnet "$cli" project response-file --output "$response_file" --source-globs "$globs_file") >&2 \
    || fail "ghul project response-file failed"
check "$(cat "$globs_file")" "src/**/*.ghul" "source globs file"
grep -q -- '^-o' "$response_file" && fail "the response file should not hold the output"
grep -q 'main.ghul' "$response_file" && fail "the response file should not hold the project's sources"
compiler="$(cd "$program" && dotnet "$cli" project compiler 2>/dev/null)"
[[ -n "$compiler" ]] || fail "ghul project compiler printed nothing"
editor_build="$scratch/editor-build"
mkdir -p "$editor_build"
(cd "$program" && eval "$compiler" "@$response_file" src/main.ghul src/greeting.ghul -o "$editor_build/greeter.wasm") >&2 \
    || fail "the compiler ghul named did not compile the project's sources with the response file"
[[ -f "$editor_build/greeter.wasm" ]] || fail "expected the editor round trip to produce greeter.wasm"

echo "project: the editor files report a manifest's problems..." >&2
if err="$(cd "$broken" && dotnet "$cli" project response-file --output "$scratch/x.rsp" 2>&1)"; then
    fail "expected ghul project response-file to fail on a bad manifest"
fi
[[ "$err" == *"ghul: ghul-project.json: name:"* ]] || fail "unexpected message from ghul project response-file: $err"
if err="$(cd "$broken" && dotnet "$cli" project compiler 2>&1)"; then
    fail "expected ghul project compiler to fail on a bad manifest"
fi
[[ "$err" == *"ghul: ghul-project.json: name:"* ]] || fail "unexpected message from ghul project compiler: $err"

# A wasm program the overriding options below build.
wasm="$scratch/wasm-greeter"
mkdir -p "$wasm/src"
cat > "$wasm/ghul-project.json" <<'JSON'
{ "name": "wasm-greeter", "targets": ["wasm"], "dependencies": { "ghul-runtime": { "version": ">=0.0.0" } } }
JSON
cat > "$wasm/src/main.ghul" <<'GHUL'
use default

entry() is
    write_line("hello with use default")
si
GHUL

echo "project: --library builds a wasm program against a library checkout..." >&2
git clone -q --depth 1 https://github.com/ghul-lang/ghul-runtime "$scratch/runtime-checkout"
# The run's stderr is kept and printed only where the run fails: a wasm run
# fetches the host and compiles before it writes anything, so a failure with
# the stderr discarded says nothing about which of those it was.
out="$(cd "$wasm" && dotnet "$cli" run --library "ghul-runtime=$scratch/runtime-checkout" \
    2>"$scratch/library-run.err")" \
    || { cat "$scratch/library-run.err" >&2; fail "ghul run with --library failed"; }
check "$out" "hello with use default" "wasm run output with --library"

if err="$(cd "$wasm" && dotnet "$cli" build --library "ghul-runtime=$scratch/no-such-core" 2>&1)"; then
    fail "expected --library naming a missing directory to fail"
fi
[[ "$err" == *"no-such-core"* ]] || fail "unexpected message for a missing library directory: $err"

echo "project: --compiler builds with the command given..." >&2
compiler="$(cd "$wasm" && dotnet "$cli" project compiler)"
out="$(cd "$wasm" && dotnet "$cli" run --compiler "$compiler" 2>/dev/null)" || fail "ghul run with --compiler failed"
check "$out" "hello with use default" "wasm run output with --compiler"

if (cd "$wasm" && dotnet "$cli" build --compiler /bin/false >/dev/null 2>&1); then
    fail "expected a build with --compiler /bin/false to fail"
fi

echo "project: GHUL_COMPILER chooses the compiler, below --compiler, and GHUL_COMPILER_VERSION is refused..." >&2
if (cd "$wasm" && GHUL_COMPILER=/bin/false dotnet "$cli" build >/dev/null 2>&1); then
    fail "expected a build with GHUL_COMPILER=/bin/false to fail"
fi
out="$(cd "$wasm" && GHUL_COMPILER=/bin/false dotnet "$cli" run --compiler "$compiler" 2>/dev/null)" || fail "--compiler did not override GHUL_COMPILER"
check "$out" "hello with use default" "wasm run output with --compiler over GHUL_COMPILER"
if err="$(cd "$wasm" && GHUL_COMPILER=/bin/false GHUL_COMPILER_VERSION=latest dotnet "$cli" build 2>&1)"; then
    fail "expected a build with GHUL_COMPILER_VERSION set to fail"
fi
[[ "$err" == *"GHUL_COMPILER_VERSION is not supported"* ]] || fail "unexpected message for GHUL_COMPILER_VERSION: $err"

echo "project: ghul new creates a project that builds and runs on wasm..." >&2
(cd "$scratch" && dotnet "$cli" new scaffolded --target wasm,llvm 2>/dev/null) || fail "ghul new failed"
[[ -f "$scratch/scaffolded/.gitignore" ]] || fail "ghul new wrote no .gitignore"
grep -q '"compiler": ">=' "$scratch/scaffolded/ghul-project.json" || fail "ghul new wrote no compiler floor"
! grep -q '"ghul-core"' "$scratch/scaffolded/ghul-project.json" || fail "ghul new wrote a ghul-core declaration"
grep -q '"ghul-runtime": { "version": ">=' "$scratch/scaffolded/ghul-project.json" || fail "ghul new wrote no ghul-runtime floor"
grep -q '"ghul-llvm": ">=' "$scratch/scaffolded/ghul-project.json" || fail "ghul new wrote no ghul-llvm floor for a project with an llvm target"
out="$(cd "$scratch/scaffolded" && dotnet "$cli" run --target wasm 2>/dev/null)" || fail "ghul run of a new project failed on wasm"
check "$out" "hello" "new project output on wasm"

echo "project: ghul new refuses a directory that is not empty..." >&2
if err="$(cd "$scratch" && dotnet "$cli" new scaffolded 2>&1)"; then
    fail "expected ghul new to refuse a non-empty directory"
fi
[[ "$err" == *"ghul: scaffolded already exists and is not empty"* ]] || fail "unexpected message from ghul new: $err"

echo "project: a manifest naming a compiler version is refused..." >&2
old_wasm="$scratch/old-wasm"
mkdir -p "$old_wasm/src"
cat > "$old_wasm/ghul-project.json" <<'JSON'
{ "name": "old-wasm", "targets": ["wasm"], "compiler": "64.11.0" }
JSON
cat > "$old_wasm/src/main.ghul" <<'GHUL'
IO.Std.write_line("hello")
GHUL
if err="$(cd "$old_wasm" && dotnet "$cli" build --target wasm 2>&1)"; then
    fail "expected a manifest naming a compiler version to fail"
fi
[[ "$err" == *"the compiler version cannot be pinned"* ]] || fail "unexpected message for a compiler version: $err"

echo "project: a manifest with a host key is refused in favour of engine..." >&2
old_host="$scratch/old-host"
mkdir -p "$old_host/src"
cat > "$old_host/ghul-project.json" <<'JSON'
{ "name": "old-host", "targets": ["wasm"], "host": { "wasm": "node" } }
JSON
cp "$old_wasm/src/main.ghul" "$old_host/src/main.ghul"
if err="$(cd "$old_host" && dotnet "$cli" build --target wasm 2>&1)"; then
    fail "expected a manifest with a host key to fail"
fi
[[ "$err" == *"host is now engine"* ]] || fail "unexpected message for a host key: $err"

echo "project: a manifest that declares no library is told the line to add..." >&2
undeclared="$scratch/undeclared"
mkdir -p "$undeclared/src"
cat > "$undeclared/ghul-project.json" <<'JSON'
{ "name": "undeclared", "targets": ["wasm"] }
JSON
cp "$old_wasm/src/main.ghul" "$undeclared/src/main.ghul"
if err="$(cd "$undeclared" && dotnet "$cli" build --target wasm 2>&1)"; then
    fail "expected a manifest with no libraries declared to fail"
fi
[[ "$err" == *'"ghul-runtime": { "version": ">='* && "$err" != *ghul-core* ]] || fail "unexpected message for undeclared libraries: $err"

echo "project: a manifest that still declares ghul-core is told to remove it..." >&2
declares_core="$scratch/declares-core"
mkdir -p "$declares_core/src"
cat > "$declares_core/ghul-project.json" <<'JSON'
{ "name": "declares-core", "targets": ["wasm"], "dependencies": { "ghul-core": { "version": ">=0.0.0" }, "ghul-runtime": { "version": ">=0.0.0" } } }
JSON
cp "$old_wasm/src/main.ghul" "$declares_core/src/main.ghul"
if err="$(cd "$declares_core" && dotnet "$cli" build 2>&1)"; then
    fail "expected a manifest declaring ghul-core to fail"
fi
[[ "$err" == *"dependencies.ghul-core"*"part of ghul-runtime"* ]] || fail "unexpected message for a ghul-core declaration: $err"

echo "project: an llvm build fetches the ghul-llvm release chosen for its compiler..." >&2
(cd "$scratch" && dotnet "$cli" new native --target llvm 2>/dev/null) || fail "ghul new --target llvm failed"
grep -q '"targets": \["llvm"\]' "$scratch/native/ghul-project.json" || fail "ghul new --target llvm wrote no llvm target"
grep -q '"ghul-llvm": ">=' "$scratch/native/ghul-project.json" || fail "ghul new --target llvm wrote no ghul-llvm floor"
if err="$(cd "$scratch/native" && GHUL_LLVM_RELEASES="file://$scratch/no-releases" dotnet "$cli" build 2>&1)"; then
    fail "expected an llvm build with no ghul-llvm release to fail"
fi
[[ "$err" == *"cannot list the ghul-llvm releases: file://$scratch/no-releases does not exist"* ]] || fail "unexpected message for a missing ghul-llvm release: $err"

echo "project: the programs under tests/projects build and print what they should..." >&2
# The runner takes its build from a configuration; this one names the CLI
# just built, which only this script knows the path of.
cat > "$config" <<JSON
{
    "default": "cli",
    "configurations": {
        "cli": { "build": "ghul-cli", "ghul": "dotnet $cli" }
    }
}
JSON
(cd "$repo_root" && dotnet tool restore >/dev/null && dotnet ghul-test tests/projects) >&2 \
    || fail "a project under tests/projects failed"

echo "project: all checks passed" >&2
