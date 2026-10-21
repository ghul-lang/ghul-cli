# ghul.repl.host

[![CI](https://img.shields.io/github/actions/workflow/status/ghul-lang/ghul-cli/ci.yml?branch=main)](https://github.com/ghul-lang/ghul-cli/actions/workflows/ci.yml?query=branch%3Amain)
[![NuGet version (ghul.repl.host)](https://img.shields.io/nuget/v/ghul.repl.host.svg)](https://www.nuget.org/packages/ghul.repl.host/)
[![License](https://img.shields.io/github/license/ghul-lang/ghul-cli)](https://github.com/ghul-lang/ghul-cli/blob/main/LICENSE)
[![ghūl](https://img.shields.io/badge/gh%C5%ABl-100%25!-information)](https://ghul.dev)

Runs a [ghul.repl](https://github.com/ghul-lang/ghul-cli/blob/main/repl/README.md)
session in the current process, on a machine that has `ghul.compiler`
installed. It compiles each cell with that compiler, loads the cell into a
load context that belongs to the session, and runs it. `ghul.repl` itself
compiles, loads and runs nothing. This package does that work, for a program
that runs cells in its own process.

## using it

One call starts a session:

```ghul
use Ghul.Repl.Host.HOST_SESSIONS

let session = HOST_SESSIONS.start(compiler_shim, runtime_assembly, true, true, line => report(line))
let result = session.submit("let x = 41\nx + 1\n")

// result.is_accepted, result.diagnostics, result.value, result.run_error

session.close()
```

- `compiler_shim` is the `ghul-compiler` command to run.
- `runtime_assembly` is the `ghul-runtime.dll` beside that compiler. The
  session copies it beside the cells so that the process can load them.
- The first flag asks for a compile server. The second asks for `use default`
  in every cell.
- The session calls the last argument with anything the host should know about
  how it is compiling cells.

`close()` ends the session. To reset, call `close()` and then `start` again.

## the compile server

The session starts one `ghul-compiler --compile-server` straight away, so that
the server warms up before the first cell, and keeps it running until
`close()`. If the server fails, stops answering or refuses a request, the
session starts the compiler once for each cell instead, and says so once.

## what `submit` returns

`submit` writes nothing to the console. It returns the diagnostics in the form
the user should see, with each cell named by its label. For a cell that threw,
it returns the report in `run_error`, and the session keeps the definitions of
that cell.

Whatever a cell writes goes to the console as it stands while the cell runs. A
host that wants that output redirects the console around the call to `submit`.

## checking whether text is complete

`HOSTED_SESSION.check(text)` says whether typed text is complete, is
incomplete, or cannot become valid whatever the user adds. When the compile
server is ready, it answers in a few milliseconds. Before that, and without a
server, `COMPLETENESS_CHECK` runs `ghul-compiler --check-complete` as a
separate process each time, which takes a few hundred milliseconds.

## completion, hover and diagnostics

`HOSTED_SESSION.complete(text, line, column)`, `hover(text, line, column)` and
`diagnostics(text)` answer questions about text that the user has not
submitted yet. They answer in terms of that text. Lines and columns count from
1. Diagnostics name the cell that the text would become by its label. Nothing
in the answer refers to the imports that the session writes in front of the
text.

The first call starts `ghul-compiler --analyse` and gives it the assembly of
each accepted cell. The session closes the analyser when it closes.

These calls need `ghul.compiler` 59.9.0 or newer. With an older compiler they
return null, the session says once that they are off, and everything else
works.

## building a session from its parts

`HOST_SESSIONS.start` assembles these public classes: `SPAWN_BACKEND`,
`SERVER_BACKEND`, `SERVER_PROCESS`, `SESSION_FILES`, `SESSION_LOAD_CONTEXT` and
`HOSTED_SESSION`. A host that wants a different arrangement can assemble them
itself, and can implement `CompileBackend` and `ServerConnection`. The default
`check` in `CompileBackend` leaves the check to the session.

## requirements

The session compiles its cells with `ghul.compiler` 59.8.0 or newer. A host
that implements `CompileBackend` needs 59.8.2 or newer to build, because older
compilers do not inherit the default `check` from another assembly.
