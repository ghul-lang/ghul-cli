# ghul.repl

[![CI](https://img.shields.io/github/actions/workflow/status/ghul-lang/ghul-cli/ci.yml?branch=main)](https://github.com/ghul-lang/ghul-cli/actions/workflows/ci.yml?query=branch%3Amain)
[![NuGet version (ghul.repl)](https://img.shields.io/nuget/v/ghul.repl.svg)](https://www.nuget.org/packages/ghul.repl/)
[![License](https://img.shields.io/github/license/ghul-lang/ghul-cli)](https://github.com/ghul-lang/ghul-cli/blob/main/LICENSE)
[![ghūl](https://img.shields.io/badge/gh%C5%ABl-100%25!-information)](https://ghul.dev)

The session behind a [ghūl](https://ghul.dev) read-eval-print loop. It keeps
track of the cells a user has submitted and works out what each new cell needs
in order to see them. It compiles nothing, loads nothing, runs nothing and
names no file: a host does those, so the same session works in a terminal, a
browser page and a notebook kernel.

## how a session works

A session is a list of accepted cells. A host compiles each cell as its own
library assembly, in its own namespace, with references to the assemblies of
the earlier cells.

The session writes a prelude of `use` lines in front of each new cell, so that
the cell can see the names the earlier cells defined. The prelude has one
`use` for each visible name, and that `use` names the cell that defined the
name most recently. A new definition of a name therefore replaces the old one
for later cells, and name lookup in the compiler works as it always does.

The prelude also repeats the `use` lines that earlier cells started with. It
starts with `use default`, unless the host creates the session with
`SESSION(false)`. It leaves out any import that the new cell writes itself, so
its length changes from cell to cell. Read the length from
`request.prelude_line_count`.

## using it

A host drives the session in three steps:

```ghul
let request = session.prepare(source)

// compile request.source, with request.references naming the earlier
// cells whose assemblies it needs. if the result is written to disk,
// name it `<request.name>.dll`

let loaded = Ghul.Repl.CELL_EXPORTS.read(assembly)
let outcome = session.accept(request, Ghul.Repl.CELL_REPLY(diagnostics, loaded))

if outcome.is_accepted then
    let run = Ghul.Repl.CELL_ENTRY.run(loaded)
fi
```

`CELL_EXPORTS.read` takes an assembly that the host has already loaded. A host
that holds its cells as bytes in one load context never writes them to disk.

The session accepts every cell that compiles, whatever the cell does when it
runs. So run a cell after the session accepts it.

## diagnostics

The host gives the compiler's diagnostics to the session in a `CELL_REPLY`. It
can give them as `CELL_DIAGNOSTIC` values, or as the lines the compiler wrote,
which the session parses.

`accept` returns the diagnostics in the form the user should see. Every
location in a cell, including a related location, names the cell by its label
(`cell-3`) and counts lines from the first line the user wrote.
`CELL_ERROR.describe` does the same for an exception that a cell threw.

## values

`CELL_DISPLAY.format` renders the value that a cell ended on, and returns
nothing for a cell that ended on a statement. It prints nothing itself, so
every host shows the same value in the same way.

Give it the runtime the cells run against with `use_runtime`. From
`ghul.runtime` 21.8.1 on, it renders the value with that runtime's `inspect`,
the same text a program gets from calling `inspect` itself. With an older
runtime, or none, it renders a collection one level deep, up to a limit on
the number of elements.

## requirements

The compiler needs to support `--submission`, `--reference` and `use default`:
`ghul.compiler` 59.8.0 or newer.
