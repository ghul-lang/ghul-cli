# AGENTS.md

Guidance for AI agents working in this repository.

## What this is

A global .NET tool for the ghūl language, written in ghūl, that runs a
`.ghul` file directly — including via a `#!/usr/bin/env ghul` shebang line
on Linux. See `.github/claude-review.md` for the fuller design summary.

## Layout

Each package is a folder of its own - `cli/`, `repl/`, `host/`,
`jupyter/`, `project/` - beside `unit-tests/` and `tests/`, with what they share
(README, LICENSE, VERSION, `Directory.*.props`, the tool manifest) at the
root. `ghul-cli.slnx` lists every project, so `dotnet build` at the root
builds them all, and `ghul-cli.code-workspace` opens each folder in VS Code.
Every package is packed into the root `nupkg/`, where the release job
looks for them.

- `cli/src/main.ghul` — the whole tool, packed as `ghul.cli` by
  `cli/ghul-cli.ghulproj`. Strips a leading `--no-cache`, then
  dispatches on the next argument: `--` skips straight to the default
  (unforced) run so a file literally named `run`/`compile`/`cache`/
  `install-compiler`/`version` can still be reached; otherwise a verb
  (`run`, `compile`, `install-compiler`, `cache`, `version`) or, with none
  of those, the argument is treated as a script to run only if it looks
  runnable — ends in `.ghul`, or is executable and starts with `#!` —
  refusing anything else unless `run` is given explicitly. `resolve_source`
  turns a script reference (a real path, or the `-` stdin marker) into the
  bytes that key its cache entry and a `materialize` function that hands
  the compiler a real `.ghul` path — reading stdin, or copying an
  extensionless file's content into one, since `ghul.compiler`'s own
  argument parser only recognises the `.ghul` extension (see the
  `resolve_source__materializes_a_dot_ghul_file_for_an_extensionless_script`
  unit test for why this needs a real regression test, not just a
  same-content smoke test). Finds its compiler through
  `Ghul.Repl.Host.COMPILER_STORE` (`~/.local/share/ghul-cli/compilers/<version>/`,
  one directory per version holding the package's `tools/net10.0/any`, several
  versions at once, highest winning where none is named) and installs into it
  on first use (or on-demand for a specific version via `install-compiler`)
  with `Ghul.Repl.Host.COMPILER_DOWNLOAD`, which fetches the package straight
  from the NuGet flat-container feed - no `dotnet tool` call, so a machine
  with only the .NET runtime works; `GHUL_COMPILER_FEED` names another feed.
  Computes a cache key from the
  script's bytes and the installed compiler version, compiles into
  `~/.cache/ghul-cli/scripts/<key>` when that cache entry doesn't already
  exist (or unconditionally under `--no-cache`), and runs the result. Both
  the install and the compile-into-a-cache-entry steps take a file lock
  (`acquire_lock`) so concurrent invocations serialise on the same work
  instead of racing; the compile path additionally builds into a
  uniquely-named scratch directory and renames it onto the real cache
  entry, so a reader's existence check never sees a half-written one and a
  losing racer just discards its redundant copy. `ghul cache clear` deletes
  the whole cache root outright; `ghul version` reports the tool's own
  `AssemblyInformationalVersion` (the same reflection idiom `ghul`'s own
  `--version` uses in `ghul/src/driver/main.ghul`) alongside the installed
  `ghul.compiler` version, if any.
- `repl/` — the `ghul.repl` package: the session core, published so that
  the browser playground and a notebook kernel build on the same one.
  `SESSION` holds the accepted cells and generates each submission's
  import prelude: `use default` unless made with `SESSION(false)`, one
  `use` per visible name naming the cell that last defined it, and the
  `use` directives earlier cells opened with, found by `USE_DIRECTIVES`
  from the text. It keeps one import per bound name, newest winning,
  since two imports of one name are a duplicate even when they name
  different things, and leaves out any the cell writes itself so the
  user's own line is the one compiled; `prelude_line_count` is per cell
  as a result. `accept` shows diagnostics as `DIAGNOSTIC_LINES.for_display`
  maps them: a cell is named `cell-<N>` and its lines counted past the
  prelude of the cell a location points into, which is why the session
  keeps each cell's prelude length. It compiles nothing, loads nothing, runs nothing and names
  no file: a host calls `prepare(source)` for the request, compiles that
  however it likes, and calls `accept(request, reply)` with what came
  back. `CELL_EXPORTS.read` takes an assembly the host has already
  loaded, so a host holding its cells as bytes never writes them out, and
  `CELL_ENTRY.run` invokes one. `CELL_DISPLAY` renders the value a cell
  ended on and prints nothing, so a terminal and a page show the same
  value the same way; a notebook wanting a MIME bundle replaces it.
  Where a host does write a cell out it
  names the assembly `<request.name>.dll`, since the compiler records a
  reference under the referenced file's own name.
- `host/` — the `ghul.repl.host` package: hosting a session in this
  process with an installed compiler, shared with the Jupyter kernel.
  `COMPILER_STORE` owns where compilers live
  (`~/.local/share/ghul-cli/compilers/<version>/`, several at once,
  highest winning where none is named) and `COMPILER_DOWNLOAD` installs
  one straight from the NuGet flat-container feed with no `dotnet tool`
  call (`GHUL_COMPILER_FEED` names another feed); `COMPILER_COMMAND` is
  how one is run (`dotnet` and its `ghul.dll`), threaded through
  everything that starts the compiler. `REFERENCE_ASSEMBLIES` finds the
  reference assemblies to point the compiler at where the machine has no
  SDK ref pack, so a script compiles with only the .NET runtime
  installed. `HOST_SESSIONS.start` assembles one. `SERVER_BACKEND` compiles on one
  `ghul-compiler --compile-server` started with the session, falling back to
  `SPAWN_BACKEND` (the compiler per cell, about a second each) for good
  when the server fails. The server also answers completeness checks
  once it is ready, which `HOSTED_SESSION.check` asks before falling back
  to `COMPLETENESS_CHECK`;
  `CELL_RUNNER` runs each cell on a background thread of its own so
  `HOSTED_SESSION.interrupt()` (any thread) can stop waiting for it, and
  `DETACHED_START` starts the long-lived compiler and analyser under
  `setsid` so the terminal's Ctrl-C does not reach them.
  `SESSION_LOAD_CONTEXT` resolves the cells' own ghūl runtime, which is
  not the one this tool was built against; `HOSTED_SESSION` is the three
  steps in order, running an accepted cell after it has joined the
  session, and writes nothing to the console. `ANALYSIS_SESSION`
  answers completion, hover and diagnostics for text not yet submitted from one
  `ghul-compiler --analyse` per session, started on first use: the text is
  analysed as `input.ghul` after the prelude it would be compiled with,
  positions move past the prelude and back, and each accepted cell reaches
  the analyser through the `add_references` request before its next
  question. `COMPLETENESS_CHECK` runs
  `ghul-compiler --check-complete` (a spawn per call, a few hundred
  milliseconds) and answers complete, incomplete or invalid.
- `cli/src/repl/` — the terminal front end. At a terminal `CELL_EDITOR`
  edits the whole cell in place (`CELL_BUFFER` its lines and cursor,
  `CELL_LAYOUT` where they fall on the screen) and `CELL_END` decides what
  Enter on its last line does, judged from the whole cell. For input that
  is not a terminal `CELL_INPUT` decides what each line does to the cell
  being entered: finished text submits unless, at a
  terminal, it ends on a statement written over several lines, which
  holds the cell open; a blank line submits (without showing the value
  after a held construct), and a line holding only `.` submits showing
  it. `INDENTATION` is where a new line starts and when a closing word
  steps it back out, `GHUL_LEXER` splits typed text into coloured runs
  with the playground editor grammar's word lists and never fails on
  half-typed input, and `PALETTE` / `COLOUR_CHOICE` / `BACKGROUND_QUERY`
  pick Light+ or Dark+ at the depth the terminal supports, from `--theme`,
  an OSC 11 query, `COLORFGBG` and `NO_COLOR`. The session needs
  `ghul.compiler` `MINIMUM_REPL_COMPILER` or newer, for `--submission`,
  `--check-complete` and `--compile-server`, and refuses to start on
  an older one rather than failing a cell at a time.
- `jupyter/` — the `ghul.jupyter` package: a Jupyter kernel, published as
  its own .NET tool (`ghul-jupyter`) so that NetMQ is a dependency of the
  kernel alone. `KERNEL` is the loop and the handlers, `CHANNEL` and
  `SIGNER` the wire format (framing at `<IDS|MSG>`, hex HMAC-SHA256 over
  the four JSON parts), `MESSAGES` and `CONTENT` what it sends, `JSON` the
  little of System.Text.Json it needs, `STREAM_WRITER` what a cell's
  console output goes to while it runs, `HEARTBEAT` the echo thread, and
  `KERNELSPEC` the `install`/`uninstall` verbs, and `CURSOR` the
  conversion between Jupyter's character offset into a cell and the line
  and column the session answers in. `PARENT_WATCH` is what
  keeps a kernel from outliving the front end that started it -
  `JPY_PARENT_PID` where Jupyter sets it, a parent that has become init
  otherwise - and `CLOSE_ONCE` settles which of the signal handler and
  the ordinary path out closes the session, since a kernel that is not
  closed leaves its compile server running. Cells are hosted through
  `ghul.repl.host`, and the compiler is found by `COMPILER_LOCATION` -
  `GHUL_COMPILER`, then the copy `ghul.cli` installs into its compiler
  store, then a store as an older `ghul.cli` installed one, then the path.
- `tests/jupyter-client/` — a front end, enough of one to drive the kernel
  over ZeroMQ from `tests/jupyter.sh`: kernel_info, cells that chain, a
  cell that does not compile, one that throws, one that writes,
  is_complete and shutdown, then a second run that leaves a kernel with
  no front end and checks it goes, and takes its compile server with it.
  It is a program rather than a unit test because it needs a kernel
  process and a compiler. It records the kernel's pid where the script
  can kill it, since a client killed before its own cleanup runs would
  otherwise leave one behind.
- `project/` — the `ghul.project` package: a ghūl project's manifest.
  `MANIFEST` and the kinds, targets, options and dependencies a manifest
  describes; `MANIFEST_READER.read(text, path)` turns manifest text into
  either a `MANIFEST` or a `MANIFEST_PROBLEM` per fault, every fault
  rather than the first, and touches no file and no network itself;
  `MANIFEST_LOCATION.find_in(directory)` finds the `ghul-project.json` in
  one directory and does not search upwards. Nothing builds from this yet
  - the commands, the source globs, fetching and the lockfile are the
  tasks under ghul-lang/ghul#3211 that follow it.
- `unit-tests/` — MSTest project covering the pure path/cache-key/
  runnable-by-default/stdin-marker/source-resolution logic.
- `tests/smoke.sh` — end-to-end test: builds the tool, points it at a real
  script under a scratch `HOME` with no `ghul.compiler` pre-installed, and
  drives it through the install/compile path, the cache path, each verb,
  the extensionless-file rules, stdin scripts, `--`, `--no-cache`, `cache
  clear`, `version`, and concurrent runs/installs against a fresh `HOME` to
  exercise the locking. This is what CI runs; run it locally the same way.

## Build and test

```sh
dotnet tool restore     # once after clone
dotnet build
dotnet test unit-tests
./tests/smoke.sh
```

## Conventions

- stdout is reserved for the run script's own output. Every subprocess this
  tool spawns for its own purposes (installing the compiler) has its stdout
  redirected and, on failure, forwarded to this tool's own stderr — never
  left to leak onto stdout.
- The cache key must change whenever the compiled output could differ.
  Today that's the script's content plus the installed compiler version;
  extend it rather than replace it if another input starts mattering.
