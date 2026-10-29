# ghul.project

[![CI](https://img.shields.io/github/actions/workflow/status/ghul-lang/ghul-cli/ci.yml?branch=main)](https://github.com/ghul-lang/ghul-cli/actions/workflows/ci.yml?query=branch%3Amain)
[![License](https://img.shields.io/github/license/ghul-lang/ghul-cli)](https://github.com/ghul-lang/ghul-cli/blob/main/LICENSE)
[![ghūl](https://img.shields.io/badge/gh%C5%ABl-100%25!-information)](https://ghul.dev)

Reads and checks a ghūl project's manifest — the `ghul-project.json` in a
project's root directory that says what the project is called, where its
sources are and what it depends on. Nothing here builds anything yet; this is
the model and the reader that later commands are written against.

## using it

```ghul
use Ghul.Project.MANIFEST_LOCATION
use Ghul.Project.MANIFEST_READER

let path = MANIFEST_LOCATION.find_in("/path/to/project")

if path? then
    let outcome = MANIFEST_READER.read(IO.File.read_all_text(path!), path!)

    case outcome
    when manifest: ReadOutcome.OK then
        write_line(manifest.name)
    when ReadOutcome.PROBLEMS then
        for problem in manifest.problems do
            write_line("ghul: {problem.describe()}")
        od
    esac
fi
```

The reader takes text and the path it came from, and touches no file and no
network itself. `MANIFEST_LOCATION.find_in` looks in one directory and does not
search upwards: a project is what its own root says it is.

## what a manifest says

```json
{
    "name": "example-app",
    "version": "0.1.0",
    "kind": "program",
    "targets": ["wasm", "dotnet"],
    "sources": ["src/**/*.ghul"],
    "compiler": "64.5.38",
    "options": {
        "underscore-access": "private",
        "global-namespace": false,
        "default-use": ["Collections", "IO.Std.write_line"],
        "define": [],
        "suppress": [],
        "warn-as-error": []
    },
    "dependencies": {
        "ghul-runtime": { "git": "https://github.com/ghul-lang/ghul-runtime", "tag": "v31.0.1" },
        "parsing": { "git": "https://example.com/libs.git", "branch": "main", "directory": "parsing" },
        "scratch": { "path": "../scratch" }
    }
}
```

Only `name` is required. What the rest default to when the manifest leaves them
out:

- `version` — nothing; a manifest does not need one
- `kind` — `program`
- `targets` — `["dotnet"]`
- `sources` — `["src/**/*.ghul"]`
- `compiler` — whatever compiler is installed
- `options` — the compiler's own defaults
- `dependencies` — nothing

Comments and a trailing comma are allowed, since a manifest is written by hand.

## what it checks

Every problem in a manifest is reported, not only the first, and each one names
the key it is about:

- a missing `name`, or one that is not lowercase letters, digits and `-`;
  a library's name also has to start with a letter, where a program's may
  start with a digit
- a key that is not one the manifest may carry, at any level: the top level,
  inside `options`, inside a dependency, or inside a git dependency, so a
  misspelling is not silently ignored
- a `kind` or a target that is not one of the two
- a member or option whose value is of the wrong shape
- a dependency with both a `git` and a `path`, or with neither
- a git dependency with neither a `tag` nor a `branch`

A manifest with any of those in it is not a manifest, so reading one returns
the problems rather than a model that is partly made up.

## what is not here yet

The lockfile, a git dependency at a branch rather than a tag, and dependencies
for the dotnet target are the tasks that follow. See [ghul-lang/ghul#3211](https://github.com/ghul-lang/ghul/issues/3211).