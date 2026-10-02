#!/usr/bin/env bash
# End-to-end test of the built ghul CLI, driving it exactly as an installed
# tool would run: pointed at a real .ghul script under a scratch HOME, with
# no pre-installed ghul.compiler, so the first invocation exercises the
# install-on-demand path and the second exercises the cache.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

dotnet build -nologo -c Debug "$repo_root/cli/ghul-cli.ghulproj" -o "$scratch/build" >&2
cli="$scratch/build/ghul-cli.dll"

export HOME="$scratch/home"
mkdir -p "$HOME"

script="$scratch/greet.ghul"
cat > "$script" <<'GHUL'
#!/usr/bin/env ghul

entry(args: string[]) is
    IO.Std.write_line("hello, {if args.count > 0 then args[0] else "world" fi}");
si
GHUL

check() {
    local got="$1" want="$2" label="$3"
    if [[ "$got" != "$want" ]]; then
        echo "smoke: $label: expected '$want', got '$got'" >&2
        exit 1
    fi
}

echo "smoke: first run (install + compile)..." >&2
out="$(dotnet "$cli" "$script" world)"
check "$out" "hello, world" "first run output"

echo "smoke: second run (cache hit)..." >&2
before="$(date +%s%N)"
out="$(dotnet "$cli" "$script" again)"
after="$(date +%s%N)"
check "$out" "hello, again" "second run output"

elapsed_ms=$(( (after - before) / 1000000 ))
if (( elapsed_ms > 2000 )); then
    echo "smoke: cache hit took ${elapsed_ms}ms - expected well under 2s, suspect it recompiled" >&2
    exit 1
fi

echo "smoke: missing script reports an error..." >&2
if dotnet "$cli" "$scratch/does-not-exist.ghul" 2>/dev/null; then
    echo "smoke: expected a non-zero exit for a missing script" >&2
    exit 1
fi

# Deliberately distinct content from every other script in this file: a
# copy of already-compiled content would let a cache hit paper over a
# broken compile path for the extensionless file itself, which is exactly
# how a prior version of this feature shipped broken - ghul.compiler's own
# argument parser only recognises a `.ghul` path, so an unrecognised
# extensionless argument was silently ignored and failed with "no entry
# point declared", but that never showed up here because this test reused
# $script's content and so always hit an already-compiled cache entry.
echo "smoke: extensionless executable script with a shebang runs by default..." >&2
noext="$scratch/greet-shebang"
cat > "$noext" <<'GHUL'
#!/usr/bin/env ghul

entry(args: string[]) is
    IO.Std.write_line("shebang, {if args.count > 0 then args[0] else "world" fi}");
si
GHUL
chmod +x "$noext"
out="$(dotnet "$cli" "$noext" no-extension)"
check "$out" "shebang, no-extension" "extensionless shebang script output"

echo "smoke: extensionless non-executable file is refused without 'run'..." >&2
plain="$scratch/greet-plain"
cp "$noext" "$plain"
chmod -x "$plain"
if dotnet "$cli" "$plain" 2>/dev/null; then
    echo "smoke: expected a non-zero exit for a non-executable, extensionless file" >&2
    exit 1
fi

echo "smoke: 'ghul run' forces the same file to run..." >&2
out="$(dotnet "$cli" run "$plain" forced)"
check "$out" "shebang, forced" "'ghul run' output"

echo "smoke: 'ghul compile' produces a cached binary and prints only its path..." >&2
compile_script="$scratch/compile-me.ghul"
cat > "$compile_script" <<'GHUL'
entry() is
    IO.Std.write_line("compiled");
si
GHUL
compiled_path="$(dotnet "$cli" compile "$compile_script")"
if [[ ! -f "$compiled_path" ]]; then
    echo "smoke: 'ghul compile' printed '$compiled_path', which is not a file" >&2
    exit 1
fi
out="$(dotnet "$compiled_path")"
check "$out" "compiled" "output of the binary 'ghul compile' produced"

echo "smoke: 'ghul install-compiler' with no version looks for the latest..." >&2
out="$(dotnet "$cli" install-compiler 2>&1)"
if [[ "$out" != *"is the latest"* && "$out" != *"updated from"* ]]; then
    echo "smoke: expected 'ghul install-compiler' to report the latest compiler or an update, got: $out" >&2
    exit 1
fi

echo "smoke: 'ghul version' reports both versions on stdout..." >&2
out="$(dotnet "$cli" version)"
if [[ "$out" != ghul\ * ]] || [[ "$out" != *ghul.compiler* ]]; then
    echo "smoke: expected 'ghul version' to report a ghul version and a ghul.compiler version, got: $out" >&2
    exit 1
fi

echo "smoke: a lone '-' runs a script read from stdin..." >&2
out="$(echo 'entry() is IO.Std.write_line("from stdin"); si' | dotnet "$cli" -)"
check "$out" "from stdin" "stdin script output"

echo "smoke: 'ghul compile -' compiles stdin and prints only its path..." >&2
compiled_from_stdin="$(echo 'entry() is IO.Std.write_line("compiled from stdin"); si' | dotnet "$cli" compile -)"
if [[ ! -f "$compiled_from_stdin" ]]; then
    echo "smoke: 'ghul compile -' printed '$compiled_from_stdin', which is not a file" >&2
    exit 1
fi
out="$(dotnet "$compiled_from_stdin")"
check "$out" "compiled from stdin" "output of the binary 'ghul compile -' produced"

echo "smoke: '--' lets a file literally named 'run' be run by default..." >&2
literal_run="$scratch/run"
cat > "$literal_run" <<'GHUL'
#!/usr/bin/env ghul

entry() is
    IO.Std.write_line("literally named run");
si
GHUL
chmod +x "$literal_run"
out="$(cd "$scratch" && dotnet "$cli" -- run)"
check "$out" "literally named run" "'ghul -- run' output"

echo "smoke: '--' also lets a file literally named 'version' be run by default..." >&2
literal_version="$scratch/version"
cat > "$literal_version" <<'GHUL'
#!/usr/bin/env ghul

entry() is
    IO.Std.write_line("literally named version");
si
GHUL
chmod +x "$literal_version"
out="$(cd "$scratch" && dotnet "$cli" -- version)"
check "$out" "literally named version" "'ghul -- version' output"

echo "smoke: '--no-cache' recompiles instead of serving a stale-looking entry..." >&2
no_cache_script="$scratch/no-cache-me.ghul"
cat > "$no_cache_script" <<'GHUL'
entry() is
    IO.Std.write_line("first version");
si
GHUL
out="$(dotnet "$cli" "$no_cache_script")"
check "$out" "first version" "first --no-cache run output"
cat > "$no_cache_script" <<'GHUL'
entry() is
    IO.Std.write_line("second version");
si
GHUL
out="$(dotnet "$cli" --no-cache "$no_cache_script")"
check "$out" "second version" "second --no-cache run output"

# '--no-cache' is documented as valid both before everything and right
# after the verb - the second form is the one that regressed silently
# behind a review finding rather than this test, so it gets its own case.
echo "smoke: '--no-cache' also works placed after the verb..." >&2
cat > "$no_cache_script" <<'GHUL'
entry() is
    IO.Std.write_line("third version");
si
GHUL
out="$(dotnet "$cli" run --no-cache "$no_cache_script")"
check "$out" "third version" "'ghul run --no-cache' output"
cat > "$no_cache_script" <<'GHUL'
entry() is
    IO.Std.write_line("fourth version");
si
GHUL
compiled_no_cache="$(dotnet "$cli" compile --no-cache "$no_cache_script")"
out="$(dotnet "$compiled_no_cache")"
check "$out" "fourth version" "'ghul compile --no-cache' output"

echo "smoke: 'ghul cache clear' empties the script cache..." >&2
cache_root="$HOME/.cache/ghul-cli/scripts"
if [[ ! -d "$cache_root" ]]; then
    echo "smoke: expected a populated cache at $cache_root before clearing" >&2
    exit 1
fi
dotnet "$cli" cache clear >&2
if [[ -d "$cache_root" ]]; then
    echo "smoke: expected $cache_root to be gone after 'ghul cache clear'" >&2
    exit 1
fi
out="$(dotnet "$cli" "$script" world)"
check "$out" "hello, world" "run after 'ghul cache clear'"

echo "smoke: concurrent runs of a brand-new script all succeed..." >&2
concurrent_script="$scratch/concurrent.ghul"
cat > "$concurrent_script" <<'GHUL'
entry() is
    IO.Std.write_line("ok");
si
GHUL
pids=()
outs_dir="$scratch/concurrent-out"
mkdir -p "$outs_dir"
for i in 1 2 3 4 5 6; do
    (dotnet "$cli" "$concurrent_script" > "$outs_dir/$i.out" 2> "$outs_dir/$i.err") &
    pids+=($!)
done
fail=0
for i in "${!pids[@]}"; do
    if ! wait "${pids[$i]}"; then
        echo "smoke: concurrent run $((i + 1)) exited non-zero:" >&2
        cat "$outs_dir/$((i + 1)).err" >&2
        fail=1
    fi
done
if (( fail )); then
    exit 1
fi
for i in 1 2 3 4 5 6; do
    check "$(cat "$outs_dir/$i.out")" "ok" "concurrent run $i output"
done

echo "smoke: concurrent 'ghul install-compiler' on a fresh HOME all succeed and agree..." >&2
fresh_home="$scratch/fresh-home"
mkdir -p "$fresh_home"
pids=()
install_outs="$scratch/install-out"
mkdir -p "$install_outs"
for i in 1 2 3; do
    (HOME="$fresh_home" dotnet "$cli" install-compiler > "$install_outs/$i.out" 2> "$install_outs/$i.err") &
    pids+=($!)
done
fail=0
for i in "${!pids[@]}"; do
    if ! wait "${pids[$i]}"; then
        echo "smoke: concurrent install $((i + 1)) exited non-zero:" >&2
        cat "$install_outs/$((i + 1)).err" >&2
        fail=1
    fi
done
if (( fail )); then
    exit 1
fi
compilers="$fresh_home/.local/share/ghul-cli/compilers"
installed_versions="$(ls "$compilers" 2>/dev/null | wc -l)"
if [[ "$installed_versions" != "1" ]]; then
    echo "smoke: expected exactly one installed compiler version after concurrent installs, found $installed_versions under $compilers" >&2
    exit 1
fi

echo "smoke: 'ghul repl' carries definitions and state from one cell to the next..." >&2
repl_in="$scratch/repl-in.txt"
cat > "$repl_in" <<'REPL'
use Collections.LIST
use IO.Std.write_line
let x = 41
let names mut = LIST[string]()
names.add("first")
inc(n: int) -> int => n + 1
class POINT(px: int, py: int) is sum() -> int => px + py; si
write_line("cell1: x is {x}")

use IO.Std.write_line
let x = "now a string"
inc(n: int) -> int => n + 100
names.add("second")

use IO.Std.write_line
write_line("{x} {inc(1)} {POINT(3, 4).sum()} {names.count}")

:quit
REPL
repl_out="$(dotnet "$cli" repl < "$repl_in" 2>"$scratch/repl.err")" || {
    echo "smoke: ghul repl exited non-zero:" >&2
    cat "$scratch/repl.err" >&2
    exit 1
}
# A redefined variable and function take effect for later cells, while the
# list declared in the first and added to in the second keeps both entries.
for expected in "cell1: x is 41" "now a string 101 7 2"; do
    if [[ "$repl_out" != *"$expected"* ]]; then
        echo "smoke: expected the repl to print '$expected', got:" >&2
        echo "$repl_out" >&2
        cat "$scratch/repl.err" >&2
        exit 1
    fi
done

echo "smoke: 'ghul repl' shows the value a submission ends on..." >&2
repl_values_in="$scratch/repl-values-in.txt"
cat > "$repl_values_in" <<'REPL'
41

"now a string"

(left = 3, right = 4)

Collections.LIST[int]([1, 2, 3])

let held = 7

IO.Std.write_line("printed")

:types off
42

:quit
REPL
repl_values_out="$(dotnet "$cli" repl < "$repl_values_in" 2>"$scratch/repl-values.err")" || {
    echo "smoke: ghul repl exited non-zero:" >&2
    cat "$scratch/repl-values.err" >&2
    exit 1
}
# A collection shows what is in it; a submission ending on a statement shows
# nothing, so `let held = 7` and the write_line contribute no value line.
for expected in "41" "now a string" "(3, 4)" "[1, 2, 3]" "printed"; do
    if [[ "$repl_values_out" != *"$expected"* ]]; then
        echo "smoke: expected the repl to show '$expected', got:" >&2
        echo "$repl_values_out" >&2
        exit 1
    fi
done
if [[ "$repl_values_out" == *"held"* ]]; then
    echo "smoke: a submission ending on a let should show nothing, got:" >&2
    echo "$repl_values_out" >&2
    exit 1
fi
# Each value follows the type of the expression the submission ended on,
# until `:types off`.
for expected in "int: 41" "(left: int, right: int): (3, 4)" "LIST[int]: [1, 2, 3]" "42"; do
    if [[ "$repl_values_out" != *"$expected"* ]]; then
        echo "smoke: expected the repl to show '$expected', got:" >&2
        echo "$repl_values_out" >&2
        exit 1
    fi
done
if [[ "$repl_values_out" == *"int: 42"* ]]; then
    echo "smoke: after :types off a value should show without its type, got:" >&2
    echo "$repl_values_out" >&2
    exit 1
fi

echo "smoke: 'ghul repl' keeps going after cells whose compiled form holds generated names..." >&2
repl_generated_in="$scratch/repl-generated-in.txt"
cat > "$repl_generated_in" <<'REPL'
let up = ["ann"] |> map(n => n.to_upper()) |> collect_mutable()

count_async() -> Tasks.TASK[int] is
    await Tasks.TASK.delay(1)
    return 7
si

struct V(x: int)

+(a: V, b: V) -> V => V(a.x + b.x)

union Tree is LEAF(value: int); NODE(left: Tree, right: Tree); si

total(t: Tree) -> int => case t when l: Tree.LEAF then l.value when n: Tree.NODE then total(n.left) + total(n.right) esac

"after {count_async().result} {(V(1) + V(2)).x} {total(Tree.NODE(Tree.LEAF(2), Tree.LEAF(3)))} {up[0]}"

:quit
REPL
repl_generated_out="$(dotnet "$cli" repl < "$repl_generated_in" 2>"$scratch/repl-generated.err")" || {
    echo "smoke: ghul repl exited non-zero:" >&2
    cat "$scratch/repl-generated.err" >&2
    exit 1
}
# A lambda, an async function, an operator and a union each compile to names
# no later cell may import; the last cell uses what each defined.
if [[ "$repl_generated_out" != *"after 7 3 5 ANN"* ]]; then
    echo "smoke: expected the repl to show 'after 7 3 5 ANN', got:" >&2
    echo "$repl_generated_out" >&2
    cat "$scratch/repl-generated.err" >&2
    exit 1
fi

echo "smoke: 'ghul repl' adds to types declared in earlier cells with partial and impl..." >&2
repl_carry_in="$scratch/repl-carry-in.txt"
cat > "$repl_carry_in" <<'REPL'
class POINT(x: int, y: int) is
    _secret: int
    init(..) is _secret = 7 si
si

area(q: POINT) -> int => q.x * q.y

partial POINT is
    norm() -> int => x * x + y * y + _secret
si

struct V(a: int)

partial V is
    doubled() -> int => a * 2
si

union Chain[T] is END; LINK(head: T, tail: Chain[T]); si

trait Printer is print() -> string; si

impl Printer for Chain[T] is
    print() -> string => if let (head, tail): LINK = self then "{head} {tail.print()}" else "end" fi
si

"carried {POINT(3, 4).norm()} {V(4).doubled()} {Chain.LINK(1, Chain.END[int]).print()}"

:quit
REPL
repl_carry_out="$(dotnet "$cli" repl < "$repl_carry_in" 2>"$scratch/repl-carry.err")" || {
    echo "smoke: ghul repl exited non-zero:" >&2
    cat "$scratch/repl-carry.err" >&2
    exit 1
}
# A cell's diagnostics and notes go to standard error with its output.
repl_carry_all="$repl_carry_out$(cat "$scratch/repl-carry.err")"
for expected in "carried 32 8 1 end" "area still takes the earlier POINT"; do
    if [[ "$repl_carry_all" != *"$expected"* ]]; then
        echo "smoke: expected the repl to show '$expected', got:" >&2
        echo "$repl_carry_out" >&2
        cat "$scratch/repl-carry.err" >&2
        exit 1
    fi
done

echo "smoke: 'ghul repl' lets a later cell use an earlier cell's underscore names..." >&2
repl_private_in="$scratch/repl-private-in.txt"
cat > "$repl_private_in" <<'REPL'
_helper(n: int) -> int => n + 1

class _HIDDEN(value: int)

class Q(v: int) is
    bump() -> int => _helper(v)
si

partial Q is
    twice() -> int => _helper(v) * 2
si

"private {_helper(1)} {_HIDDEN(42).value} {Q(3).twice()}"

:quit
REPL
repl_private_out="$(dotnet "$cli" repl < "$repl_private_in" 2>"$scratch/repl-private.err")" || {
    echo "smoke: ghul repl exited non-zero:" >&2
    cat "$scratch/repl-private.err" >&2
    exit 1
}
if [[ "$repl_private_out" != *"private 2 42 8"* ]]; then
    echo "smoke: expected the repl to show 'private 2 42 8', got:" >&2
    echo "$repl_private_out" >&2
    cat "$scratch/repl-private.err" >&2
    exit 1
fi

echo "smoke: 'ghul repl' extends a class declared in an earlier submission..." >&2
repl_extend_in="$scratch/repl-extend-in.txt"
cat > "$repl_extend_in" <<'REPL'
class SHAPE is
    init() is si
    name() -> string => "shape"
si

class CIRCLE: SHAPE is
    init() is super.init() si
    name() -> string => "circle"
si

CIRCLE().name()

:quit
REPL
repl_extend_out="$(dotnet "$cli" repl < "$repl_extend_in" 2>"$scratch/repl-extend.err")" || {
    echo "smoke: ghul repl exited non-zero:" >&2
    cat "$scratch/repl-extend.err" >&2
    exit 1
}
if [[ "$repl_extend_out" != *"circle"* ]]; then
    echo "smoke: expected a subclass of an earlier submission's class to work, got:" >&2
    echo "$repl_extend_out" >&2
    cat "$scratch/repl-extend.err" >&2
    exit 1
fi

echo "smoke: a redefinition reads the value it replaces..." >&2
repl_redefine_in="$scratch/repl-redefine-in.txt"
cat > "$repl_redefine_in" <<'REPL'
let x = 10, y = 20
let x = x + y
x
:quit
REPL
repl_redefine_out="$(dotnet "$cli" repl < "$repl_redefine_in" 2>"$scratch/repl-redefine.err")" || true
if [[ "$repl_redefine_out" != *"30"* ]]; then
    echo "smoke: expected 'let x = x + y' to read the earlier x, got:" >&2
    echo "$repl_redefine_out" >&2
    cat "$scratch/repl-redefine.err" >&2
    exit 1
fi

echo "smoke: a line holding only . ends a cell and is not compiled..." >&2
repl_dot_in="$scratch/repl-dot-in.txt"
cat > "$repl_dot_in" <<'REPL'
.
41
.
let unfinished = (1 +
.
"after the dot"
:quit
REPL
repl_dot_out="$(dotnet "$cli" repl < "$repl_dot_in" 2>"$scratch/repl-dot.err")" || true
for expected in "41" "after the dot"; do
    if [[ "$repl_dot_out" != *"$expected"* ]]; then
        echo "smoke: expected the repl to show '$expected' around a . line, got:" >&2
        echo "$repl_dot_out" >&2
        cat "$scratch/repl-dot.err" >&2
        exit 1
    fi
done
if ! grep -q "^cell-2: " "$scratch/repl-dot.err"; then
    echo "smoke: expected the . line to end the unfinished cell and report it, stderr was:" >&2
    cat "$scratch/repl-dot.err" >&2
    exit 1
fi

echo "smoke: a cell that does not compile leaves the session unchanged..." >&2
repl_bad_in="$scratch/repl-bad-in.txt"
cat > "$repl_bad_in" <<'REPL'
let y = 1

let z = no_such_name

use IO.Std.write_line
write_line("{y}")

:quit
REPL
repl_bad_out="$(dotnet "$cli" repl < "$repl_bad_in" 2>"$scratch/repl-bad.err")" || true
if [[ "$repl_bad_out" != *"1"* ]]; then
    echo "smoke: expected the repl to still know y after a failed cell, got:" >&2
    echo "$repl_bad_out" >&2
    exit 1
fi
if ! grep -q "no_such_name" "$scratch/repl-bad.err"; then
    echo "smoke: expected the failed cell to be reported, stderr was:" >&2
    cat "$scratch/repl-bad.err" >&2
    exit 1
fi
if ! grep -q "^cell-[0-9]*: " "$scratch/repl-bad.err" || grep -q "/tmp" "$scratch/repl-bad.err"; then
    echo "smoke: expected the failed cell to be named by its label, not its file, stderr was:" >&2
    cat "$scratch/repl-bad.err" >&2
    exit 1
fi
dotnet "$cli" repl --no-server < "$repl_bad_in" > /dev/null 2> "$scratch/repl-bad-spawn.err" || true
if ! grep -q "^cell-[0-9]*: " "$scratch/repl-bad-spawn.err" || grep -q "/tmp" "$scratch/repl-bad-spawn.err"; then
    echo "smoke: expected --no-server to name the failed cell by its label too, stderr was:" >&2
    cat "$scratch/repl-bad-spawn.err" >&2
    exit 1
fi

# The compile server is the default, so every session above went through
# it; none of them should have had to fall back.
for err in "$scratch/repl.err" "$scratch/repl-values.err" "$scratch/repl-extend.err" "$scratch/repl-bad.err"; do
    if grep -q "instead" "$err"; then
        echo "smoke: a session fell back from the compile server:" >&2
        cat "$err" >&2
        exit 1
    fi
done

echo "smoke: 'ghul repl --no-server' starts the compiler for each cell..." >&2
repl_spawn_out="$(dotnet "$cli" repl --no-server < "$repl_in" 2>"$scratch/repl-spawn.err")" || {
    echo "smoke: ghul repl --no-server exited non-zero:" >&2
    cat "$scratch/repl-spawn.err" >&2
    exit 1
}
if [[ "$repl_spawn_out" != *"now a string 101 7 2"* ]]; then
    echo "smoke: expected the spawn backend to give the same answers, got:" >&2
    echo "$repl_spawn_out" >&2
    cat "$scratch/repl-spawn.err" >&2
    exit 1
fi

echo "smoke: an import typed on its own line stays in force..." >&2
repl_use_in="$scratch/repl-use-in.txt"
cat > "$repl_use_in" <<'REPL'
use IO.Path.combine
combine("a", "b")
:quit
REPL
repl_use_out="$(dotnet "$cli" repl < "$repl_use_in" 2>"$scratch/repl-use.err")" || true
if [[ "$repl_use_out" != *"a/b"* ]]; then
    echo "smoke: expected an import from one cell to reach the next, got:" >&2
    echo "$repl_use_out" >&2
    cat "$scratch/repl-use.err" >&2
    exit 1
fi

echo "smoke: 'ghul repl --no-default-use' leaves the default imports out..." >&2
repl_bare_in="$scratch/repl-bare-in.txt"
cat > "$repl_bare_in" <<'REPL'
write_line("unimported")
use IO.Std.write_line
write_line("imported")
:quit
REPL
repl_bare_out="$(dotnet "$cli" repl --no-default-use < "$repl_bare_in" 2>"$scratch/repl-bare.err")" || true
if [[ "$repl_bare_out" == *"unimported"* || "$repl_bare_out" != *"imported"* ]]; then
    echo "smoke: expected write_line only once it was imported, got:" >&2
    echo "$repl_bare_out" >&2
    cat "$scratch/repl-bare.err" >&2
    exit 1
fi

echo "smoke: ':reset' forgets what earlier cells defined..." >&2
repl_reset_in="$scratch/repl-reset-in.txt"
cat > "$repl_reset_in" <<'REPL'
let secret = 5
:reset
let after = 6
secret
after
:quit
REPL
repl_reset_out="$(dotnet "$cli" repl < "$repl_reset_in" 2>"$scratch/repl-reset.err")" || true
if [[ "$repl_reset_out" != *"6"* || "$repl_reset_out" == *"5"* ]]; then
    echo "smoke: expected only the cell after the reset to be known, got:" >&2
    echo "$repl_reset_out" >&2
    exit 1
fi
if ! grep -q "secret" "$scratch/repl-reset.err"; then
    echo "smoke: expected the name from before the reset to be reported unknown, stderr was:" >&2
    cat "$scratch/repl-reset.err" >&2
    exit 1
fi

echo "smoke: ':complete' and ':hover' see an earlier cell's names..." >&2
repl_analysis_in="$scratch/repl-analysis-in.txt"
cat > "$repl_analysis_in" <<'REPL'
let answer = 41
:complete ans
:hover answer
:quit
REPL
repl_analysis_out="$(dotnet "$cli" repl < "$repl_analysis_in" 2>"$scratch/repl-analysis.err")" || true
for expected in "answer" "answer: int"; do
    if [[ "$repl_analysis_out" != *"$expected"* ]]; then
        echo "smoke: expected completion and hover to show '$expected', got:" >&2
        echo "$repl_analysis_out" >&2
        cat "$scratch/repl-analysis.err" >&2
        exit 1
    fi
done

compile_servers() {
    pgrep -af -- "--compile-server|--analyse" | grep -F "$HOME/" || true
}

if [[ -n "$(compile_servers)" ]]; then
    echo "smoke: a compile server outlived its session:" >&2
    compile_servers >&2
    exit 1
fi

echo "smoke: a signal ends the session and its compile server..." >&2
repl_fifo="$scratch/repl-fifo"
mkfifo "$repl_fifo"
dotnet "$cli" repl < "$repl_fifo" > /dev/null 2>&1 &
repl_pid=$!
exec 3> "$repl_fifo"
for _ in $(seq 60); do
    [[ -n "$(compile_servers)" ]] && break
    sleep 0.5
done
if [[ -z "$(compile_servers)" ]]; then
    echo "smoke: the session never started its compile server" >&2
    exit 1
fi
kill -TERM "$repl_pid"
wait "$repl_pid" || true
exec 3>&-
for _ in $(seq 20); do
    [[ -z "$(compile_servers)" ]] && break
    sleep 0.25
done
if [[ -n "$(compile_servers)" ]]; then
    echo "smoke: a compile server outlived a session ended by a signal:" >&2
    compile_servers >&2
    exit 1
fi

echo "smoke: all checks passed" >&2
