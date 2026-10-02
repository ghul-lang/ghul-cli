# ghul.jupyter

[![CI](https://img.shields.io/github/actions/workflow/status/degory/ghul-cli/ci.yml?branch=main)](https://github.com/degory/ghul-cli/actions/workflows/ci.yml?query=branch%3Amain)
[![NuGet version (ghul.jupyter)](https://img.shields.io/nuget/v/ghul.jupyter.svg)](https://www.nuget.org/packages/ghul.jupyter/)
[![License](https://img.shields.io/github/license/degory/ghul-cli)](https://github.com/degory/ghul-cli/blob/main/LICENSE)
[![ghūl](https://img.shields.io/badge/gh%C5%ABl-100%25!-information)](https://ghul.dev)

A [Jupyter](https://jupyter.org) kernel for [ghūl](https://ghul.dev). It
compiles and runs notebook cells as a
[ghul.repl](https://github.com/degory/ghul-cli/blob/main/repl/README.md)
session, with one assembly for each cell.

## installing

```sh
dotnet tool install -g ghul.jupyter
ghul-jupyter install
```

`ghul-jupyter install` writes the kernelspec, which is the file a front end
finds a kernel by, and prints where it wrote it. It writes under
`JUPYTER_DATA_DIR` when that is set, and under
`~/.local/share/jupyter/kernels/ghul` otherwise. `ghul-jupyter uninstall`
removes the kernelspec.

A front end runs `ghul-jupyter kernel <connection-file>` to start the kernel.
You do not type that command yourself.

The kernel compiles cells with a `ghul-compiler` that is already on the
machine. It looks first for the compiler that `GHUL_COMPILER` names, then for
the copy that `ghul.cli` installs in its compiler store, and then for a
`ghul-compiler` on the path. The simplest way to get one is to install
`ghul.cli` and run any script once.

## using it from VS Code

1. Install the
   [Jupyter extension](https://marketplace.visualstudio.com/items?itemName=ms-toolsai.jupyter).
2. Reload the window (**Developer: Reload Window**). The Jupyter extension
   looks for kernelspecs when it starts, so it does not see a new one until you
   reload.
3. Open or create a `.ipynb` file.
4. Click the kernel picker at the top right, choose **Jupyter Kernel...**, and
   pick **ghūl**.

The
[ghūl extension](https://marketplace.visualstudio.com/items?itemName=degory.ghul)
highlights cells as ghūl, if you have it installed.

## the kernelspec

The kernelspec names the tool by its absolute path, because VS Code does not
look up a bare command name on `PATH`.

The kernelspec also sets an environment for the kernel. It puts the .NET
installation and the tools directory on `PATH`, and it sets `DOTNET_ROOT` when
.NET is not installed in a default location. A front end started from a
desktop launcher does not have the environment of your shell, and this lets it
start the kernel anyway.

`install` takes both the path and the environment from the process that runs
it. Run `ghul-jupyter install` again after you move the tool or .NET.

## cells

The kernel compiles each cell as its own assembly, in its own namespace, with
references to the earlier cells. A new definition of a name replaces the old
one for later cells, and does not change cells that have already run. A cell
that ends on a value shows the value.

A cell that does not compile leaves the session as it was. The kernel keeps a
cell that throws, because the cell compiled and later cells can use its
definitions. The kernel sends what a cell writes as the cell writes it, a line
at a time. A cell cannot read standard input.

To restart, the front end starts the kernel process again, so a restart
begins a new session.

The [ghul.repl README](https://github.com/degory/ghul-cli/blob/main/repl/README.md)
describes the session. The REPL section of
[the CLI's README](https://github.com/degory/ghul-cli/blob/main/README.md)
describes what a cell can do.

## the protocol

The kernel implements protocol 5.3 over the five ZeroMQ sockets, and signs
messages with the key in the connection file. It answers these requests:

- `kernel_info_request`
- `execute_request`. It publishes `stream`, `execute_result` and `error`
  messages as the cell runs.
- `is_complete_request`. The kernel answers the way the terminal decides what
  Enter does: a value is complete, a `let` or a definition holds the cell
  open for more, unfinished text is incomplete, and a blank line at the end
  completes whatever is above it.
- `complete_request` and `inspect_request`. The session's analyser gives the
  answers, so a name that an earlier cell declared completes in a later cell,
  and you can inspect it there. When no analyser is available, the kernel
  answers with nothing rather than an error.
- `shutdown_request` and `interrupt_request`
