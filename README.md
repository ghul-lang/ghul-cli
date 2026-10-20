# ghūl CLI

[![CI](https://img.shields.io/github/actions/workflow/status/degory/ghul-cli/ci.yml?branch=main)](https://github.com/degory/ghul-cli/actions/workflows/ci.yml?query=branch%3Amain)
[![NuGet version (ghul.cli)](https://img.shields.io/nuget/v/ghul.cli.svg)](https://www.nuget.org/packages/ghul.cli/)
[![License](https://img.shields.io/github/license/degory/ghul-cli)](https://github.com/degory/ghul-cli/blob/main/LICENSE)
[![ghūl](https://img.shields.io/badge/gh%C5%ABl-100%25!-information)](https://ghul.dev)

`ghul` runs a [ghūl](https://ghul.dev) script directly, with no project file.
On Linux a script can start with a `#!` line and run as a command. `ghul repl`
starts an interactive session.

```ghul
#!/usr/bin/env ghul

entry(args: string[]) is
    write_line("hello, {if args.count > 0 then args[0] else "world" fi}")
si
```

```sh
chmod +x greet.ghul
./greet.ghul world
# hello, world
```

Without the `#!` line, name the script:

```sh
ghul greet.ghul world
```

A script that declares no namespace gets the compiler's default imports
(`use default`), so it can use `write_line`, the pipes and the collections
with no `use`. This needs `ghul.compiler` 60.2.0 or newer. With an older
compiler, a script writes its own `use` lines.

## installing

There are two ways to install `ghul`, and which to use depends on whether the
machine has .NET.

### as a .NET tool

```sh
dotnet tool install -g ghul.cli
```

This is the complete tool: scripts, `#!` scripts, projects for both targets,
the REPL and the Jupyter kernel. `dotnet tool` comes with the .NET 10 SDK;
once installed, `ghul` runs on the .NET runtime alone.

The first time it runs, `ghul` downloads its own copy of `ghul.compiler` into
`~/.cache/ghul-cli/compilers/dotnet` (under `$XDG_CACHE_HOME/ghul-cli` where that
is set), straight from the NuGet feed. Each way of running the compiler has a
directory of its own under `compilers`, named as `GHUL_COMPILER_HOST` names it:
`dotnet`, `native` and `wasm`, with `llvm` for the compiler built for llvm.
There is nothing else to set up.
Several compiler versions can be installed at once; where none is named, the
highest installed is the one used.

`dotnet tool update -g ghul.cli` updates it.

### without .NET

```sh
curl -fsSL https://raw.githubusercontent.com/ghul-lang/ghul-cli/main/install.sh | sh
```

This installs `ghul` as a native executable, built with .NET Native AOT, which
needs nothing installed but the C library: no .NET runtime and no SDK. It is
built for Linux on x64 and on arm64, a Raspberry Pi 4 or 5 among them. The
archive holds the tool alone, so the compiler is never out of date with it:
the first build fetches one into the compiler cache above, the wasm-built
compiler under Node by default. The tool goes into `~/.local/opt/ghul`, linked
from `~/.local/bin/ghul`. `sh install.sh --help` lists the options, and
`--dry-run` reports what it would do.

`ghul update` updates it in place.

Without .NET, `ghul` builds projects for the llvm and wasm targets. An llvm
build links a native executable with `ghul-llvm`, which `ghul` fetches the
first time it is needed. A wasm build runs with Node.js 22.19 or later on the
22 line, 24.15 or later on the 24 line, or 25 or later; where the machine has
none, `ghul` says so and that `ghul install node` brings one in, and on Linux
x64 that the llvm target builds a native executable without it. Both fetch
ghul-core and ghul-runtime with `git`.

Without .NET, the compiler itself is the wasm-built one, run by Node: a
single archive every release publishes for every platform, fetched the first
time it is needed. The Node it runs under is the one on `PATH`, or the one
`ghul install node` brought in. On a machine with no Node, `ghul` fetches the
Native AOT compiler instead, which is published for Linux x64 only; on arm64
there is none, so the machine needs Node, and `ghul install node` brings one in.

Which machines that covers follows from the builds that exist. `ghul` is a
.NET tool except as its Linux x64 native archive, so a machine with no .NET at
all is Linux x64 or arm64. `ghul` builds for wasm and, on Linux x64 and arm64, llvm; it does not
build for .NET, which is the .NET SDK's job, with a `.ghulproj` and `dotnet build`.

A script, `ghul script.ghul`, a `#!/usr/bin/env ghul` script or one read from
standard input, runs wherever a target can be built for it: wasm, or the
target `GHUL_TARGET` names. A script is cached, by the script, the target,
the compiler and the libraries and `ghul-llvm` it was built with, so it
compiles once. A script that compiles says nothing.

The REPL works without .NET on Linux x64 and arm64. With no .NET to host the
cells, `ghul repl` starts the native session, as `ghul repl --target llvm`
does: each cell is compiled natively and run in a host process that keeps every
earlier cell loaded, in about one to two seconds a cell. It needs `ghul-llvm`,
which `ghul` fetches the first time. Ctrl-C ends a running cell and keeps the
session, and completion and hover work.

What does not work without .NET, today: **the Jupyter kernel.** Each cell is
compiled to a .NET assembly and run inside the tool, which the native build
cannot do.

A wasm program can use only what the wasm target supports, which is much less
than .NET:

- the core library is a small subset of the .NET base class library, so most
  `System.*` APIs do not exist there, and a program naming one is told the
  name is not found
- files live in memory: a program can read only what it has written itself,
  and what it writes is also written beneath the working directory
- asynchronous functions, `await` and `decimal` are not supported yet

[ghul.dev/webassembly.html](https://ghul.dev/webassembly.html) lists what the
wasm target supports, and is kept current as the gaps close.

## commands

```sh
ghul [--no-cache] [--] <script> [args...]   # run a script (see below)
ghul run [--no-cache] <script> [args...]    # run any file as a script
ghul compile [--no-cache] <script.ghul>     # compile, and print the path to the result
ghul new <name> [--target <names>]           # create a project to build and run
ghul add <name> <git-url>                    # depend on the newest release of a library (writes ^newest)
ghul rosetta <task>[/<part>] [<directory>]  # fetch a Rosetta Code solution as a project
ghul build [--target <name>] [--debug] [--optimise <0-3>] [overrides]  # build the project in this directory
ghul run [--target <name>] [--debug] [--optimise <0-3>] [overrides] [-- args...]  # build, then run it
ghul project response-file|compiler         # what editors read (see below)
ghul install <compiler|wasmtime|node|llvm>  # install or update a component
ghul update [--check]                     # update ghul and every installed tool to the newest release
ghul cache clear                            # empty the compiled-script cache
ghul repl [--no-server] [--no-default-use]  # start an interactive session
ghul version                                # print the versions of ghul and ghul.compiler
ghul --help, or -h after ghul or any command  # print the usage
```

With no command, `ghul` runs a file only if it looks like a script. A script
is a file whose name ends in `.ghul`, or an executable file that starts with
`#!`. `ghul` refuses any other file and names `ghul run` as the way to run it.

`ghul run` runs the file it is given, whatever the file looks like. A
`#!/usr/bin/env ghul` line runs the script this way.

To run a script named `run`, `new`, `compile`, `cache`, `install-compiler`,
`update` or `version`, write `ghul -- <name>`.

`ghul compile` builds the script exactly as running it would, into the same
cache entry, and prints the path to what runs: for wasm the loader, which
`node` runs, and for llvm the executable. It installs the compiler first if
it needs to, and it does not run the result. The path is the only thing it
writes to standard output, so `node $(ghul compile script.ghul)` runs it.
Compiler messages go to standard error.

`ghul install compiler` installs `ghul.compiler` into `ghul`'s own compiler
store, so that the first script does not wait for the install. It installs the
compiler this machine uses: the managed compiler where there is a .NET host to
run it, and the wasm-built compiler, run by Node.js, everywhere else, with a
Node.js fetched first where there is none. A Native AOT compiler is installed
only by an earlier release's install, and kept up to date while it is there.
`GHUL_COMPILER_HOST` (`wasm`, `dotnet` or `native`) names the one to use
instead. `install compiler` installs the latest release, and nothing if it is
already installed. A version cannot be chosen: the compiler, ghul-llvm,
Node.js, wasmtime and the compiler's libraries ghul-core and ghul-runtime are
tools, and always the newest release. What a project depends on is pinned in its
manifest's `dependencies`. `GHUL_COMPILER_FEED` names a different feed to download from, for a
mirror or an offline network.

`ghul install llvm` installs the ghul-llvm tool the llvm target links with. It
needs no compiler: it takes the newest release. It
is released for Linux on x64 and arm64. `ghul install wasmtime`
installs the wasmtime host that runs wasm programs where there is no Node.js;
a run that needs it and finds it missing downloads the latest release first.
`ghul install node` brings a Node.js distribution into the cache from
nodejs.org — the newest LTS release that runs the wasm target, falling back
to the newest release when no LTS does, verified against the release's
published checksums — for a machine that wants the node host
without installing Node system-wide.

`ghul install compiler --llvm` installs the compiler built with the llvm
target instead, a native executable that builds for the `wasm` and `llvm`
targets only, into a store of its own. A project chooses it with
`"compiler-build": "llvm"` in its manifest; `"default"`, or no entry, keeps
the ordinary compiler. It is published for Linux on x64 only.

`ghul install-compiler` and `ghul install-compiler --llvm` still work, with a
note pointing at the new spellings: `ghul install compiler` and `ghul install
compiler --llvm`.

`ghul update` updates a `ghul` installed without .NET to the latest release. It runs that release's
own install script, after checking it against the published sha256, so the
tool is replaced the same way a fresh install puts it in place. A `ghul`
installed as a .NET tool is updated by `dotnet tool update -g ghul.cli`
instead, which `ghul update` prints. It then brings every component that is
installed up to date: each compiler, ghul-llvm, Node.js and the wasmtime host.
A component that is not installed is left alone and not mentioned, and what
is said is what is being done or what went wrong. `--check` reports what has
a newer release and changes nothing. `GHUL_CLI_API` and `GHUL_CLI_RELEASES`
name a mirror, as they do for `install.sh`. Everything `ghul` says about its
own work begins `ghul: `.

A `-` in place of the script reads the source from standard input. This
works for running and for compiling:

```sh
echo 'entry() is IO.Std.write_line("hi") si' | ghul -
curl -fsSL https://example.com/greet.ghul | ghul -
```

`--no-cache` compiles the script again even if the cache already holds a
result for it. Write it before the script, or before `run` or `compile`. Use
it when a cached result looks wrong. `ghul cache clear` empties the whole
cache.

## projects

A directory holding a `ghul-project.json` is a project. The manifest names
the project, says whether it is a program or a library, which targets it
builds for and where its sources are:

```json
{
    "name": "greeter",
    "kind": "program",
    "targets": ["llvm", "wasm"],
    "sources": ["src/**/*.ghul"]
}
```

`targets` lists the targets the project may be built for: `wasm` and `llvm`.
`ghul new` writes `["wasm"]` unless `--target` names others. A manifest that
lists `dotnet` is refused, with a message pointing at the .NET SDK.

A manifest's `tools` names the oldest release of a tool the project was written
with, as the same ranges a dependency takes:

```json
{
    "name": "greeter",
    "kind": "program",
    "targets": ["llvm", "wasm"],
    "sources": ["src/**/*.ghul"],
    "tools": { "compiler": ">=66.7.0", "ghul-llvm": ">=1.0.0" }
}
```

The tools a project can name are `compiler` and, for an llvm build,
`ghul-llvm`. `ghul new` writes a floor (`>=`) for each tool its targets need,
the release in use when it ran. Tools are always the newest release, so a
floor never holds a newer one back: it makes a machine whose compiler is older
update it, and a range that does not admit the newest release is reported. A
compiler named with `--compiler` or `GHUL_COMPILER` below the floor is used,
with a warning. A tool a manifest does not name is the newest release, and no
tool is ever an error for lacking a floor.

`ghul build` builds the project in the current directory into
`out/<target>/`. `ghul run` builds it and then runs it, passing the arguments
after `--` to the program; `ghul run <script>` still runs a script, project
or not.

A project that lists one target builds that one. Where it lists several,
`--target` names the one to build, or failing that `GHUL_TARGET` in the
environment. Otherwise `ghul` takes the first target in order that the
machine can build:
- wasm, which needs nothing at build time; the run finds something to run
  the module under, as the engines section below describes

A manifest's `prefer`, such as `"prefer": ["wasm"]`, puts the targets it
names first, and every one it names has to be among `targets`. When `ghul`
passes over a target it cannot build, it says what it built for instead in one
line; choosing the first in order, it says nothing. Where no listed target
can be built, it says why for each and builds nothing.

### workspaces and collections

Two other kinds describe a directory that owns no sources and builds nothing.
`ghul build` and `ghul run` refuse them, naming the kind.

A `workspace` lists the projects under it in `members`, as paths or globs
relative to its own directory, so an editor that opens the directory can start
one analyser for each:

```json
{
    "kind": "workspace",
    "members": ["cli", "project", "tools/*"]
}
```

A `collection` holds projects that are independent programs rather than parts
of one, such as a directory of examples or test cases:

```json
{
    "kind": "collection"
}
```

Neither carries `targets`, `sources` or `dependencies`, and `name` is optional.
An editor does not analyse the contents of a collection as one project, and a
project nested inside any other manifest's directory belongs to the nearest
manifest above it.

## engines and global defaults

A wasm program needs an engine to run the module: wasmtime, or Node.js
through the loader the compiler writes. (The host is the machine `ghul` runs
on.) Which engine is chosen in three steps, each filling only what the one
before leaves unset.

1. The project manifest names it: `"engine": { "wasm": "wasmtime" }` or
   `"engine": { "wasm": "node" }`. The key was once `host`, which is refused
   with a message.
2. The machine's global configuration file,
   `~/.config/ghul/config.json`, names a default for every project that
   does not choose:

   ```json
   { "defaults": { "engine": { "wasm": "wasmtime" } } }
   ```

3. Nothing said anywhere, the built-in default is node, which runs these
   builds faster than the wasmtime host; where the machine has no node that
   runs the wasm target, a run says so and names `ghul install node`. The
   wasmtime host runs only where the manifest or the global file names it,
   and is fetched where it is missing. A host named by the manifest or the
   global file is honoured rather than swapped.

A project that names an engine itself is never overridden by the global file.
The built-in order a build follows is wasm; llvm is never chosen
automatically.

When a run chooses the wasmtime host and finds it missing, it downloads the
newest release first, as the compiler is downloaded on first use.
`ghul install wasmtime` does the same ahead of time, and `ghul update`
refreshes ghul itself and every component already installed.

The compiler's messages go to standard error, and a failed build exits
with the compiler's status. The build uses the newest installed
`ghul.compiler`, which a manifest cannot pin: a manifest with a `compiler` is
refused.

`--debug` builds with debug information into `out/<target>-debug/`, beside
the ordinary build rather than over it, and `ghul run --debug` runs that build.
`--optimise <0-3>` sets the llvm target's optimisation level, which is
otherwise 2, or 0 for a debug build; a level other than that default adds
`-O<n>` to the directory, as in `out/llvm-O3/` or `out/llvm-debug-O2/`. The
manifest's `options` may name a default level, `"optimise": 3`, which the
command line overrides. A chosen level needs ghul.compiler 65.16.0 or newer.

The `wasm` target writes
a WebAssembly module and the JavaScript loader the compiler puts beside it,
and runs under Node.js 22.19 or later on the 22 line, 24.15 or later on the 24
line, or 25 or later, which `ghul` checks before running it; Node 23 cannot
run it. A wasm build compiles in two libraries,
fetched from Git into `~/.cache/ghul-cli/libraries`: ghul-core, which gives
the built-in types their members, and then ghul-runtime, which supplies the
pipes and the rest of `Ghul`. They are libraries with releases of their own, so
a project declares both in its `dependencies`, which `ghul new` writes:

```json
"dependencies": {
    "ghul-core": { "version": ">=0.75.1" },
    "ghul-runtime": { "version": ">=29.1.1" }
}
```

The repository is known, so a version alone is enough. It is a range as for
any dependency, and a build uses the newest release it admits: `>=` is a floor
and admits a newer major version, where `^` stops at the next one. `>=0.0.0`
says the project accepts any release. A `path` uses a checkout instead. A
project for wasm or llvm that leaves either out is refused, and the message
names the lines to add with the newest release as the floor. The releases are
listed on every build; where GitHub cannot be reached, the release used last
is used again. A library that needs a newer compiler than the installed one
fails to compile with the compiler's own error, and `ghul update` brings the
compiler up to date.

A script is not a project and declares nothing: it is built with the newest
release of each.

Any other entry in `dependencies` names a source library a wasm build compiles
in after those two: a directory holding a `ghul-project.json` that lists
`wasm` among its targets, declared by `path` or as a `git` repository at a
`version`, and fetched into the same cache. A `version` is a bare release
(exactly that one), `^1.2.3` (at least that, below the next major), `~1.2.3`
(at least that, below the next minor) or `>=1.2.3`, and resolves to the newest
matching release, listed on every build, with the one used last where GitHub
cannot be reached. A `tag` is the older spelling of an exact version. A library's own dependencies are
compiled in too, each before the libraries that use it, and a `path` in a
library's manifest is relative to that library.

A wasm build needs `ghul.compiler` 64.15.0 or newer. Where the newest
installed is older, the build installs the newest release and uses that.

Two options override the manifest for one build, which is how a repository
tests its own checkout. `--compiler <command>` builds with the command given,
such as `dotnet /path/to/publish/ghul.dll`, in place of an installed compiler;
the libraries are the newest releases, as for any build. `--library <name>=<path>`, which can be given more than once,
compiles the source library `name` (`ghul-core` or `ghul-runtime`) from the
directory at `path`. Both work with `build`, `run` and `ghul project
response-file`, and `--compiler` with `ghul project compiler`.

Two environment variables override the manifest for every build, which is
how a test harness that drives `ghul` chooses the compiler for all of them.
`GHUL_COMPILER` is a compiler command, as `--compiler` takes one, which
overrides it. `GHUL_COMPILER_VERSION` is refused.

`GHUL_COMPILER_HOST` picks how the compiler is run, for every build and for
`ghul project compiler`, so an editor follows it too. Unset, `ghul` chooses:
the managed compiler where there is .NET, and otherwise the wasm-built one
under Node.

- `wasm`: the wasm-built compiler, run by Node; `ghul` fetches a Node where
  there is none it can run.
- `dotnet`: the managed compiler, run by the .NET host.
- `native`: the Native AOT compiler, built for Linux x64 only.

Each is installed as it is needed into a directory of its own under the
compiler cache, `compilers/<host>`. Any other value, or a host this machine
cannot have, is an error naming the value. A compiler given as a command, by `--compiler` or
`GHUL_COMPILER`, runs as given whatever the variable says, and a manifest
naming the llvm-built compiler with `compiler-build` keeps it.

### hello world on WebAssembly

`ghul new` creates a project, then `ghul run` builds and runs it:

```sh
ghul new hello
cd hello
ghul run      # builds into out/wasm/ and runs it under Node.js
```

`ghul new`'s `--target` takes `wasm` or `llvm`, or both separated by a comma,
and defaults to `wasm`.
The new directory holds the manifest, `ghul-project.json`; `src/main.ghul`,
whose entry writes `hello`; and a `.gitignore` for `out/`. A directory that
already exists and is not empty is refused. The program is:

```ghul
use IO.Std.write_line

entry() is
    write_line("hello")
si
```

The first build installs the compiler and fetches the libraries; later builds
reuse them. A project's sources get no implicit imports, so they `use` what
they call, or start with `use default` for `write_line`, the pipes and the
collections.

### native executables

A project that lists the `llvm` target builds a native executable for Linux
x86-64 into `out/llvm/`, and `ghul run --target llvm` runs it directly. With
ghul.compiler 65.8.0 or newer the executable needs an x86-64-v3 CPU (AVX2 and
BMI2, from about 2013 on). The
first such build also fetches the newest `ghul-llvm` release,
the linker and runtime it links with, into the same cache; setting `GHUL_LLVM`
to a `ghul-llvm` executable uses that one instead. The compiler's code
generation for this target is in its early stages, and a build reports what it
cannot yet compile.

A debug build for llvm carries DWARF line tables and variables, is
unoptimised unless `--optimise` says otherwise, and needs ghul.compiler
65.14.0 or newer. Where the manifest names no compiler and the newest installed
is older, the newest release is installed for it. `objdump` shows the source
beside the machine code, and `gdb` steps through it:

```sh
ghul build --debug
objdump -d -S out/llvm-debug/<name>
gdb out/llvm-debug/<name>
```

### Rosetta Code solutions

`ghul rosetta <task>` fetches a solution from
[ghul-rosetta-code](https://github.com/ghul-lang/ghul-rosetta-code) into a project, named by the
task's slug as it appears in the repository's `tasks/` and in its address on ghul.dev, such as
`100-doors`. A task solved more than one way is named with the part as well,
`accumulator-factory/02-widening-from-integer-to-float`, and naming the task alone lists its
parts. The project goes into a directory of that name, or the one given after it.

The repository's index says what the solution needs, and everything is fetched at the commit
the index was made from: its source into `src/`, and any file it reads beside the manifest,
which is where it is run from. The manifest lists the targets the solution passes on: `llvm`
where it builds and passes as a native executable, and `wasm` where it runs as WebAssembly. `ghul rosetta` prints the
`ghul run` that runs it, with its command-line arguments where it takes any.

```sh
ghul rosetta 100-doors
cd 100-doors
ghul run --target llvm
```

## tools for editors

Two commands exist for editors and other tools that analyse a project the
way its build compiles it, rather than for building it:

```sh
ghul project response-file --output <path> [--source-globs <path>] [--target <name>]
ghul project compiler [--json]
```

`ghul project response-file` writes the options a build passes the compiler,
one flag a line with its value, without the output or the project's own
sources: the client passes it to the compiler as `@<path>`. A wasm build's
core library is in it too, as its `--library-source` declaration and its
files. `--source-globs` also writes the manifest's source globs, one a line
and relative to the manifest, for the client to expand and watch.
Where the manifest lists more than one target, `--target` names the one,
or failing that `GHUL_TARGET`, and otherwise the target is chosen as a build
chooses it, `prefer` included, except that wasm counts as buildable without
Node.js, since an editor analyses the project rather than running it.

`ghul project compiler` prints the command that runs the compiler the
project builds with, installing it first if need be, as the only line on
standard output. That is the newest
installed, so it can change after a compiler is installed. On a machine with
no .NET it is the wasm-built compiler run by Node.js, which serves analysis
from 66.1.0. The program is named by its full path where `PATH` finds it, so
a client started with a different `PATH` runs the same one. `--json` prints
the command as a JSON array of strings, the program first, for a client to
start as it stands rather than splitting a command line.

Both report a manifest's problems on standard error and exit non-zero.

## the REPL

`ghul repl` starts an interactive session. You type a cell, the session
compiles and runs it, and everything the cell defines stays available to the
cells after it:

```plaintext
1> let names mut = LIST[string]()
 | names.add("first")
2> for name in ["second", "third"] do
 |     names.add(name)
 | od
 | names
["first", "second", "third"]
```

### submitting a cell

The session submits a cell when you finish a line that is an expression or a
call, and then shows the value. So you can write a short program as one cell
that ends on the value you want:

```plaintext
1> let x = 123
 | let y = 2
 | x * y
246
```

The session keeps the cell open after a line that finishes a `let`, an
assignment or a definition, because those lines set something up for the
lines that follow. The `|` prompt stays and the next line joins the same
cell. The session also keeps the cell open when:

- an `if`, `case`, loop or `try` written over several lines closes
- a line leaves something open: a block with no closing keyword, an open
  bracket, or an operator with nothing after it
- a line ends in a `\` on its own. The session drops the `\`. A `\` that
  ends a longer operator, such as `/\`, is part of the code.

A blank line submits the cell. So does a line that holds only `.`, and so
does Alt-Enter from any line of the cell.

If no further typing can make the text valid, the session submits it as soon
as every block it opens is closed, and reports its errors then. This means
the session reports a mistake inside an `if`, a loop or a definition after
you close the block, and the closing lines stay part of the same cell.

### seeing a value

A cell that ends on a value shows the value, so `names` above needs no
`write_line`. A cell that ends on a statement shows nothing.

A cell that you end with a blank line after a construct written over several
lines also shows nothing, because a construct like that usually does something
rather than produce a value. End the cell with `.` or Alt-Enter to see its
value:

```plaintext
3> if names.count > 2 then
 |     "several"
 | else
 |     "few"
 | fi
 | .
several
```

To show a value from partway through a cell, call `display` with it. It is
written the same way as a cell's value, at the point the cell reaches the call.
In a notebook, `display(value, id)` shows the value under an id, and
`update_display(value, id)` replaces what that id shows. A terminal cannot
redraw a line it has already written, so there `update_display` writes the new
value as another line. `display` and `update_display` come from the ghūl
runtime, so a session offers them when its compiler ships ghul.runtime
21.11.0 or newer.

In a notebook, a value that offers an image through `Ghul.Renderable`, such as
a ghul.raster `IMAGE`, shows as that image beside its text.

### cell numbers

The prompt shows the number of the next cell. Every cell you submit takes a
number, including a cell that does not compile. A command such as `:cells`
takes no number.

Messages name a cell by its label, `cell-3` for the third cell. Code names
the same cell `cell3`, so `cell3.x` is the third cell's `x`.

`:cells` lists the cells so far. For each cell it shows the first line and
how the cell ended: `ok`, `failed`, `threw` or `interrupted`. `:cells 3`
shows the whole of the third cell.

`:rerun 3` submits the text of the third cell again as a new cell with its
own number. `:cells` lists the new cell as a rerun of 3.

`:rerun 3..` submits the third cell again, and then every later cell that ran
to the end the first time, in order. It skips the cells that failed, threw or
were interrupted, and it stops at the first cell that does not run to the end
this time. Use it after you redefine something that later cells used: it
brings those cells up to date.

`:edit 3` puts the text of the third cell at the next prompt, where you can
change it and submit it as a new cell.

### imports

Every cell gets the compiler's default imports (`use default`), so it can use
`write_line`, the pipes and the collections with no `use`. `ghul repl
--no-default-use` leaves them out. A `use` that you type applies to every
later cell, as a definition does:

```plaintext
1> use IO.Path.combine
 | combine("a", "b")
a/b
```

### redefining a name

A new definition of a name replaces the old one for the cells that follow.
It does not change cells that have already run: they keep the definition
they were compiled with. The new definition can have a different type, so
`let x = 41` and a later `let x = "now a string"` both work.

A new definition can read the value it replaces. After `let x = 10, y = 20`,
the cell `let x = x + y` makes `x` 30.

### errors

The session shows an error or a warning with the line it points at, and puts
carets under the part it means. At a terminal with colour, errors are red and
warnings are yellow. When the same message applies at several places on one
line, the session shows the message once with a caret under each place:

```plaintext
5> nope + nope
cell-5: 1,1..1,5: error: symbol not found: nope
 1 | nope + nope
   | ^^^^   ^^^^
```

### editing

At a terminal you edit the whole cell in place, however many lines it has.

| key | what it does |
| --- | --- |
| Up, Down | move between the lines of the cell, and into history past its first or last line |
| Enter on the last line | submit the cell, or start a new line if the cell stays open |
| Enter on an earlier line | start a new line there |
| Alt-Enter | submit the cell from any line, and show the value it ends on |
| Backspace at the start of a line | join the line to the line above |
| Home, End, or Ctrl-A, Ctrl-E | go to the start or the end of the line |
| Ctrl-Left, Ctrl-Right, or Alt-B, Alt-F | move by a word |
| Ctrl-U, Ctrl-K | delete to the start or the end of the line |
| Ctrl-W | delete the word before the cursor |
| Ctrl-L | clear the screen |
| Tab | complete the name at the cursor |
| Shift-Tab | show what the name at the cursor is, as `:hover` does |
| Ctrl-D in an empty cell | leave the session |

The session indents each new line for you. A line that opens a block makes
the next line start four spaces further in. These lines open a block: a line
that ends in `is`, `then`, `else`, `do`, `try` or `=>`, a `case` or `catch`
line, and a line with an open bracket. A line that starts with `si`, `fi`,
`od`, `esac`, `yrt`, `else`, `elif`, `when`, `catch` or `finally` moves back
out as you type the word. Backspace in the indent of a line removes one whole
step. After that, the session leaves the indent of that line to you.

The session takes a pasted block as it is, with its own indentation and its
blank lines.

### history

Up from the first line of a cell, and Down from the last line, step through
earlier cells. The session brings each one back whole. History includes the
cells of earlier sessions. The session keeps the last thousand cells in
`$XDG_STATE_HOME/ghul-cli/history`, or in `~/.local/state/ghul-cli/history`
when `XDG_STATE_HOME` is not set.

### completion

Tab completes the name at the cursor from everything the session has defined.
When more than one name fits, Tab writes in the part the names share and
lists them below the cell.

Tab again opens the list so that you can choose from it. Tab, Right and Down
move to the next name. Shift-Tab, Left and Up move back. The session writes
each name into the cell as you move to it. Enter keeps the name. Escape
restores what you typed. Any other key keeps the name and carries on typing.

### Ctrl-C

At the prompt, Ctrl-C sets aside the cell you are typing. The text stays on
the screen marked `^C`, and a new prompt with the same number replaces it.
The session did not submit the cell, so the cell takes no number and `:cells`
does not list it. Up brings it back from history. With nothing typed, Ctrl-C
does nothing.

While a cell is running, Ctrl-C interrupts it and brings the prompt back. The
session keeps everything it has defined, including the definitions of the
interrupted cell. .NET cannot stop a running thread from outside, so the
session abandons the cell rather than ending it. The cell might keep running
in the background, using a core or writing output, until it finishes or the
session ends.

### commands

`:help` lists the commands. `:reset` starts a new session. `:quit` leaves.

`:complete TEXT` lists what could follow TEXT. `:hover TEXT` shows what the
end of TEXT names. Both know everything the session has defined:

```plaintext
1> let answer = 41
 |
2> :complete ans
answer
2> :hover answer
answer: int
```

`:type EXPRESSION` shows the type of an expression without running it:

```plaintext
2> :type [answer, 1] |> map(n => "{n}")
Pipe[string]
```

A submission that ends on a value shows the value after the type of the
expression it ended on, as `:type` would show it:

```plaintext
3> let x = {i for i in 0..5}
4> x
Pipe[int]: [0, 1, 2, 3, 4]
5> x |> count()
int: 5
```

`:types off` shows values without their types, and `:types on` shows them
again. Where the analyser cannot answer, the value is shown alone.

`:complete`, `:hover` and `:type` need `ghul.compiler` 59.9.0 or newer. With
an older compiler, each one says that it is not available, and values are shown
without their types. The first time you use one, or a submission first ends on
a value, the session starts a compiler in analysis mode, which takes a second
or two. After that an answer takes tens of milliseconds, or a little longer
straight after a cell, because the analyser reads the new cell first.

`:ref FILE` makes an assembly available to every later cell. `:nuget PACKAGE`
does the same for a NuGet package and everything the package depends on. It
uses the latest stable release unless you write a version after the name.
Call a C# extension method as the static method it is:

```plaintext
1> :nuget Humanizer.Core 2.14.1
restoring Humanizer.Core...
referenced Humanizer
1> Humanizer.StringHumanizeExtensions.humanize("some_long_identifier")
some long identifier
```

To restore a package, the session runs `dotnet publish` on a small project
that references it, so the first package takes a few seconds. `:reset` starts
a session with no references.

`:save FILE` writes the cells that ran to the end to FILE, each after a
`// cell N` line. `:load FILE` submits the cells in FILE in order, each as a
new cell, and stops at the first cell that does not run to the end. `:load`
submits a file with no `// cell N` lines as one cell.

### colour

The session colours what you type as you type it. It uses the colours that
ghul.dev and the playground use: VS Code's Dark+ on a dark background and
Light+ on a light background.

The session asks the terminal for its background colour. If the terminal does
not answer, the session reads `COLORFGBG`. If neither gives an answer, the
session uses the dark colours. `ghul repl --theme dark`, `--theme light` or
`--theme none` chooses the colours for it.

`COLORTERM` and `TERM` decide between 24-bit colour, the 256-colour palette
and the standard sixteen colours. The session uses no colour when `NO_COLOR`
is set, or when the input or the output is not a terminal.

### input from a pipe or a file

When the input is not a terminal, the session reads it a line at a time, with
no editing. The rules for submitting a cell are the same, with one
difference: a construct written over several lines submits the cell when it
closes. A `.` line and a line that ends in `\` work as they do at a terminal.

### speed

The session starts one compiler before the first prompt and keeps it running,
so the compiler warms up while you type. The first cell takes most of a
second. After that, a cell takes a few tens of milliseconds from Enter to its
answer. That time includes the check for whether the line finishes the cell.

`ghul repl --no-server` starts the compiler again for each cell, which takes
about a second a cell. The session switches to this by itself, and says so
once, if the running compiler fails or stops answering.

### how a session is built

The session compiles each cell as its own small library and loads it. A later
cell can use the types, functions and variables of the cells before it,
including the ones whose names start with `_`. A member whose name starts
with `_` stays private to its class, as it does in any ghūl program. A later
cell can also add to a type from an earlier cell with `partial` or `impl`.

The session needs `ghul.compiler` 59.8.0 or newer, and says so if an older
compiler is installed. Names that start with `_` cross cells only with
`ghul.runtime` 21.4.0 or newer.

Three packages make up the REPL:

- [`ghul.repl`](https://github.com/degory/ghul-cli/blob/main/repl/README.md)
  is the session: the cells it has accepted, the imports each new cell needs,
  and the names each compiled cell exports. It compiles nothing and runs
  nothing, so a browser page or a notebook kernel can use it with its own
  compiler.
- [`ghul.repl.host`](https://github.com/degory/ghul-cli/blob/main/host/README.md)
  compiles cells with the installed compiler, loads them and runs them in
  the current process. `ghul repl` uses it, and so can another program.
- [`ghul.jupyter`](https://github.com/degory/ghul-cli/blob/main/jupyter/README.md)
  is a Jupyter kernel built on both.

## how it works

`ghul` compiles a script once for each combination of script content and
compiler version, and caches the result under `~/.cache/ghul-cli/scripts`.
The next run of an unchanged script runs the cached build.

`ghul` passes everything after the script path to the script as its
command-line arguments. The exit code of the script becomes the exit code of
`ghul`.

`ghul` takes a file lock while it installs the compiler, and another while it
compiles a script. When several scripts start at once, one process does each
piece of work and the others wait for it, so no process reads a half-written
result.

`ghul` has no options for reference assemblies. A script can use whatever
`ghul.compiler` finds by itself.

## building from source

```sh
dotnet tool restore
dotnet build
dotnet test unit-tests
./tests/smoke.sh
```
