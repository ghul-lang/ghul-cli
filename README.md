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
`~/.cache/ghul-cli/compilers` (`$XDG_CACHE_HOME/ghul-cli/compilers` where that
is set), straight from the NuGet feed. There is nothing else to set up.
Several compiler versions can be installed at once; where none is named, the
highest installed is the one used.

`dotnet tool update -g ghul.cli` updates it.

### without .NET

```sh
curl -fsSL https://raw.githubusercontent.com/ghul-lang/ghul-cli/main/install.sh | sh
```

This installs `ghul` and the compiler as native executables, built with .NET
Native AOT, which need nothing installed but the C library: no .NET runtime
and no SDK. It is built for Linux on x64 only. The tool goes into
`~/.local/opt/ghul`, linked from `~/.local/bin/ghul`, and the compiler it
ships goes into the compiler cache above. `sh install.sh --help` lists the
options, and `--dry-run` reports what it would do.

`ghul update` updates it in place.

Without .NET, `ghul` builds projects for the llvm and wasm targets. An llvm
build links a native executable with `ghul-llvm`, which `ghul` fetches the
first time it is needed. A wasm build runs with Node.js 22.19 or later on the
22 line, 24.15 or later on the 24 line, or 25 or later, which has to be
installed separately. Both fetch ghul-core and ghul-runtime with `git`.

Which machines that covers follows from the builds that exist. `ghul` is a
.NET tool except as its Linux x64 native archive, and the compilers that build
without a .NET SDK, the Native AOT compiler and the llvm-built one, are
published for Linux x64 only. So a machine with no .NET at all is Linux x64,
and there `ghul` builds for llvm. A machine with a .NET runtime but no SDK can
run `ghul` and build for wasm and, on Linux x64, llvm, but not for dotnet.

A script, `ghul script.ghul`, a `#!/usr/bin/env ghul` script or one read from
standard input, runs wherever a target can be built for it. A script needs
only the .NET runtime for the dotnet target, so it takes dotnet wherever .NET
is installed, and otherwise llvm, then wasm, as a project does.
`GHUL_TARGET` names the target instead. A script built for llvm or wasm is
cached, by the script, the target, the compiler and the libraries and
`ghul-llvm` it was built with, so it compiles once. A script that compiles
says nothing; where `ghul` built it for llvm or wasm because dotnet could not
be, the build says so in one line.

What does not work without .NET, today:

- **`ghul compile`**, which writes a script's .NET assembly.
- **The REPL and the Jupyter kernel.** Each cell is compiled to a .NET
  assembly and run inside the tool, which the native build cannot do.
- **The dotnet target.** Building one needs the .NET reference assemblies
  that come with .NET.

The REPL on wasm is planned in
[ghul-lang/ghul#3480](https://github.com/ghul-lang/ghul/issues/3480).

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
ghul rosetta <task>[/<part>] [<directory>]  # fetch a Rosetta Code solution as a project
ghul build [--target <name>] [--debug] [--optimise <0-3>] [overrides]  # build the project in this directory
ghul run [--target <name>] [--debug] [--optimise <0-3>] [overrides] [-- args...]  # build, then run it
ghul project response-file|compiler         # what editors read (see below)
ghul install-compiler [--llvm] [version]    # install or update ghul.compiler
ghul update [--version <tag>] [--check]     # update ghul itself
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

`ghul compile` compiles the script and prints the path to the compiled
binary. It installs the compiler first if it needs to, and it does not run
the result. The path is the only thing it writes to standard output, so
`$(ghul compile script.ghul)` captures it. Compiler messages go to standard
error.

`ghul install-compiler` installs `ghul.compiler` into `ghul`'s own compiler
store, so that the first script does not wait for the install. With no
version, it installs the latest release, or updates to it. With a version, it
installs exactly that version, older or newer, and does nothing if that
version is already installed. `GHUL_COMPILER_FEED` names a different feed to
download from, for a mirror or an offline network.

`ghul install-compiler --llvm` installs the compiler built with the llvm
target instead, a native executable that builds for the `wasm` and `llvm`
targets only, into a store of its own. A project chooses it with
`"compiler-build": "llvm"` in its manifest; `"default"`, or no entry, keeps
the ordinary compiler. It is published for Linux on x64 only.

`ghul update` updates a `ghul` installed without .NET to the latest release,
or to the release `--version` names, older or newer. It runs that release's
own install script, after checking it against the published sha256, so the
tool is replaced the same way a fresh install puts it in place. `--check`
reports whether there is anything to update and changes nothing. A `ghul`
installed as a .NET tool is updated by `dotnet tool update -g ghul.cli`
instead, which `ghul update` prints. `GHUL_CLI_API` and `GHUL_CLI_RELEASES`
name a mirror, as they do for `install.sh`.

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
    "targets": ["dotnet", "llvm", "wasm"],
    "sources": ["src/**/*.ghul"]
}
```

`targets` lists the targets the project may be built for. `ghul new` writes
all three, `["dotnet", "llvm", "wasm"]`, unless `--target` names others.

`ghul build` builds the project in the current directory into
`out/<target>/`. `ghul run` builds it and then runs it, passing the arguments
after `--` to the program; `ghul run <script>` still runs a script, project
or not.

A project that lists one target builds that one. Where it lists several,
`--target` names the one to build, or failing that `GHUL_TARGET` in the
environment. Otherwise `ghul` takes the first target in order that the
machine can build:
- dotnet, where a .NET SDK is installed
- llvm, where `ghul-llvm` is cached or can be fetched
- wasm, where Node.js is installed to run it

A manifest's `prefer`, such as `"prefer": ["llvm"]`, puts the targets it
names first, and every one it names has to be among `targets`. When `ghul`
cannot build for dotnet, it says what it built for instead and why in one line,
as in `ghul: building for llvm (no .NET SDK)`; choosing dotnet, or a target
`prefer` puts first, it says nothing. Where no listed target
can be built, it says why for each and builds nothing.

The compiler's messages go to standard error, and a failed build exits
with the compiler's status. `compiler` in the manifest names the
`ghul.compiler` version to build with, which is installed if need be, or
`latest` for the newest published release; without it, the newest installed is
used.

`--debug` builds with debug information into `out/<target>-debug/`, beside
the ordinary build rather than over it, and `ghul run --debug` runs that build.
`--optimise <0-3>` sets the llvm target's optimisation level, which is
otherwise 2, or 0 for a debug build; a level other than that default adds
`-O<n>` to the directory, as in `out/llvm-O3/` or `out/llvm-debug-O2/`. The
manifest's `options` may name a default level, `"optimise": 3`, which the
command line overrides. A chosen level needs ghul.compiler 65.16.0 or newer.

The `dotnet` target writes `<name>.exe` (or `<name>.dll` for a library), with
`ghul-runtime.dll` beside it, and runs with `dotnet`. The `wasm` target writes
a WebAssembly module and the JavaScript loader the compiler puts beside it,
and runs under Node.js 22.19 or later on the 22 line, 24.15 or later on the 24
line, or 25 or later, which `ghul` checks before running it; Node 23 cannot
run it. A wasm build compiles in two libraries,
fetched from Git into `~/.cache/ghul-cli/libraries`: ghul-core, which gives
the built-in types their members, and then ghul-runtime, which supplies the
pipes and the rest of `Ghul`. Declaring `ghul-core` or `ghul-runtime` in the
manifest's `dependencies`, at a `tag` or a `path`, uses that instead.

A compiler declares the oldest release of each library it works with in the
`requirements.json` beside it, and each library release declares the oldest
compiler that builds it in a `requirements.json` of its own. A build uses the
newest release that satisfies both, and keeps the choice for a day; where no
release does, the build stops with a message naming both versions. A compiler
from before the declaration gets the release this tool pins for it.

Any other entry in `dependencies` names a source library a wasm build compiles
in after those two: a directory holding a `ghul-project.json` that lists
`wasm` among its targets, declared by `path` or as a `git` repository at a
`tag`, and fetched into the same cache. A library's own dependencies are
compiled in too, each before the libraries that use it, and a `path` in a
library's manifest is relative to that library. A `dotnet` build refuses a
manifest with source library dependencies.

A wasm build needs `ghul.compiler` 64.15.0 or newer. Where the newest
installed is older, the build installs the newest release and uses that; a
manifest whose `compiler` names an older version is an error, as is an older
version named by `GHUL_COMPILER_VERSION`.

Two options override the manifest for one build, which is how a repository
tests its own checkout. `--compiler <command>` builds with the command given,
such as `dotnet /path/to/publish/ghul.dll`, in place of an installed compiler;
the libraries for it are chosen from the `requirements.json` beside it, or by
the version it prints when run with no arguments where there is none. `--library <name>=<path>`, which can be given more than once,
compiles the source library `name` (`ghul-core` or `ghul-runtime`) from the
directory at `path`. Both work with `build`, `run` and `ghul project
response-file`, and `--compiler` with `ghul project compiler`.

Two environment variables override the manifest for every build, which is
how a test harness that drives `ghul` chooses the compiler for all of them.
`GHUL_COMPILER` is a compiler command, as `--compiler` takes one, and
`GHUL_COMPILER_VERSION` a `ghul.compiler` version to install and use, or
`latest`. `--compiler` overrides both, and setting both is an error.

### hello world on WebAssembly

`ghul new` creates a project, then `ghul run` builds and runs it:

```sh
ghul new hello --target dotnet,wasm
cd hello
ghul run --target wasm      # builds into out/wasm/ and runs it under Node.js
ghul run --target dotnet    # builds into out/dotnet/ and runs it with dotnet
```

`ghul new`'s `--target` takes `dotnet`, `wasm` or `llvm`, or several separated by
commas, and defaults to all three.
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
first such build also fetches the `ghul-llvm` release pinned for the compiler,
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
which is where it is run from. The manifest lists the targets the solution passes on: `dotnet`
where this machine has .NET, `llvm` where it builds and passes as a native executable, and `wasm`
where it runs as WebAssembly. One that draws with ghul.raster compiles it in from source, which a
`dotnet` build cannot do, so it builds for `llvm` and `wasm` only. `ghul rosetta` prints the
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
ghul project compiler
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
standard output. With no `compiler` in the manifest that is the newest
installed, so it can change after a compiler is installed.

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
