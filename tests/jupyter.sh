#!/usr/bin/env bash
# End-to-end test of the Jupyter kernel: builds it, gives it a connection
# file with ports nothing else holds, and drives it over ZeroMQ the way a
# notebook does - kernel_info, cells that chain, a cell that does not
# compile, one that throws, one that writes, is_complete, and shutdown - and
# reports how long the kernel takes to start and to run its first cell.
#
# The kernel needs a ghul.compiler to build cells with, so this installs
# one under a scratch HOME first, through the CLI that owns that, and the
# kernel then finds it where the CLI put it.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"

# A kernel is a process with a compile server of its own, so one left
# behind costs memory until someone notices. The client kills the kernel
# it started, but a client that is itself killed - a timeout, a signal -
# never gets that far, so the pid it records is killed here as well.
cleanup() {
    for pid_file in "$scratch"/*/kernel.pid; do
        [[ -f "$pid_file" ]] || continue

        local_pid="$(cat "$pid_file")"

        if [[ -n "$local_pid" ]] && kill -0 "$local_pid" 2>/dev/null; then
            kill "$local_pid" 2>/dev/null || true
        fi
    done

    rm -rf "$scratch"
}

trap cleanup EXIT INT TERM

# Built before the scratch HOME is set, since building needs the real one's
# package cache and local tool manifest.
dotnet build -nologo -c Debug "$repo_root/cli/ghul-cli.ghulproj" -o "$scratch/cli" >&2
dotnet build -nologo -c Debug "$repo_root/jupyter/jupyter.ghulproj" -o "$scratch/kernel" >&2
dotnet build -nologo -c Debug "$repo_root/tests/jupyter-client/jupyter-client.ghulproj" -o "$scratch/client" >&2

# The kernel has to find a compiler the way an installed one would, so it
# gets a HOME of its own with nothing in it.
export HOME="$scratch/home"
mkdir -p "$HOME"

echo "jupyter: installing a compiler under the scratch HOME..." >&2

# The kernel runs each cell in this process, so it needs the managed
# compiler, which ghul installs only where it is named.
dotnet "$scratch/cli/ghul-cli.dll" install compiler --compiler-host dotnet >/dev/null

echo "jupyter: driving the kernel..." >&2

# Traced, so that the one thing the trace exists to answer - did a
# request arrive - is answered here rather than the next time someone
# wonders. The kernel inherits this stderr, so both streams land in the
# log and the run still shows on the terminal.
GHUL_JUPYTER_TRACE=1 dotnet "$scratch/client/jupyter-client.dll" \
    "$scratch/kernel/ghul.jupyter.dll" "$scratch/session" 2> >(tee "$scratch/traced.log" >&2)

for expected in "recv shell kernel_info_request" "recv shell execute_request" "send iopub execute_result"; do
    if ! grep -q "trace: $expected" "$scratch/traced.log"; then
        echo "jupyter: GHUL_JUPYTER_TRACE did not report '$expected'" >&2
        exit 1
    fi
done

echo "jupyter: the trace reported what crossed the wire"

echo "jupyter: a kernel whose front end goes away..." >&2

dotnet "$scratch/client/jupyter-client.dll" \
    "$scratch/kernel/ghul.jupyter.dll" "$scratch/abandoned" --abandon 2> "$scratch/abandoned.log"

abandoned_pid="$(cat "$scratch/abandoned/kernel.pid")"

# The compile server the kernel started, read as that kernel's own
# children rather than by matching command lines - another session on
# this machine runs compile servers of its own, and they are not this
# test's to notice or to kill.
children=""

for stat in /proc/[0-9]*/stat; do
    [[ -r "$stat" ]] || continue

    fields="$(sed 's/.*) //' "$stat" 2>/dev/null)" || continue

    if [[ "$(echo "$fields" | cut -d' ' -f2)" == "$abandoned_pid" ]]; then
        children="$children $(basename "$(dirname "$stat")")"
    fi
done

waited=0

while kill -0 "$abandoned_pid" 2>/dev/null; do
    if (( waited >= 30 )); then
        echo "jupyter: the kernel outlived its front end" >&2
        kill "$abandoned_pid" 2>/dev/null || true
        exit 1
    fi

    sleep 1
    waited=$(( waited + 1 ))
done

echo "jupyter: the kernel went with its front end, after ${waited}s"

# It has to have gone because it noticed, not by accident: the kernel
# says why it stopped, and that line is what this is checking for.
if ! grep -q "stopping: whatever started it has gone" "$scratch/abandoned.log"; then
    echo "jupyter: the kernel went, but not because it noticed its front end had:" >&2
    cat "$scratch/abandoned.log" >&2
    exit 1
fi

for child in $children; do
    if kill -0 "$child" 2>/dev/null; then
        echo "jupyter: the kernel's compile server ($child) outlived it" >&2
        kill "$child" 2>/dev/null || true
        exit 1
    fi
done

if [[ -n "$children" ]]; then
    echo "jupyter: and took its compile server with it"
fi

# The compile server the kernel started has to have gone with it. Read
# from the kernel's own session directory rather than by matching command
# lines, which would match this script's own.
for pid_file in "$scratch"/*/kernel.pid; do
    [[ -f "$pid_file" ]] || continue

    left="$(cat "$pid_file")"

    if kill -0 "$left" 2>/dev/null; then
        echo "jupyter: a kernel ($left) survived the run" >&2
        exit 1
    fi
done

echo "jupyter: a kernel asked to stop by a signal..." >&2

mkdir -p "$scratch/signalled"

dotnet "$scratch/kernel/ghul.jupyter.dll" kernel "$scratch/abandoned/connection.json" \
    > "$scratch/signalled.log" 2>&1 &
signalled_pid=$!

# Recorded where the trap looks, like the ones the client starts: a
# script killed while waiting below would otherwise leave this one behind,
# which is the leak this is all about.
echo "$signalled_pid" > "$scratch/signalled/kernel.pid"

sleep 3
kill -TERM "$signalled_pid"

waited=0

while kill -0 "$signalled_pid" 2>/dev/null; do
    if (( waited >= 20 )); then
        echo "jupyter: the kernel ignored SIGTERM" >&2
        kill -9 "$signalled_pid" 2>/dev/null || true
        exit 1
    fi

    sleep 1
    waited=$(( waited + 1 ))
done

wait "$signalled_pid" 2>/dev/null || true

echo "jupyter: the kernel went on SIGTERM, after ${waited}s"

echo "jupyter: the kernelspec..." >&2

export JUPYTER_DATA_DIR="$scratch/jupyter"

dotnet "$scratch/kernel/ghul.jupyter.dll" install >/dev/null

spec="$JUPYTER_DATA_DIR/kernels/ghul/kernel.json"

if [[ ! -f "$spec" ]]; then
    echo "jupyter: install wrote no kernelspec at $spec" >&2
    exit 1
fi

for want in '"kernel"' '"{connection_file}"' '"language":"ghul"' '"interrupt_mode":"message"'; do
    if ! grep -qF -- "$want" "$spec"; then
        echo "jupyter: the kernelspec is missing $want" >&2
        cat "$spec" >&2
        exit 1
    fi
done

# A front end started from a desktop launcher has neither the shell's PATH
# nor its DOTNET_ROOT, so the kernelspec has to name everything it needs:
# the command by absolute path, and an environment to run it in.
if ! grep -qF -- "\"argv\":[\"/" "$spec"; then
    echo "jupyter: the kernelspec does not name its command by absolute path" >&2
    cat "$spec" >&2
    exit 1
fi

echo "jupyter: driving the kernel from its kernelspec, with no inherited environment..." >&2

dotnet "$scratch/client/jupyter-client.dll" "$spec" "$scratch/from-spec"

dotnet "$scratch/kernel/ghul.jupyter.dll" uninstall >/dev/null

if [[ -d "$JUPYTER_DATA_DIR/kernels/ghul" ]]; then
    echo "jupyter: uninstall left the kernelspec behind" >&2
    exit 1
fi

echo "jupyter: all checks passed"
