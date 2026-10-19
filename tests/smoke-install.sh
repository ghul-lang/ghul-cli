#!/usr/bin/env bash
# Installs the Native AOT archive the way a user does and uses it, with nothing
# of .NET on the machine's PATH: install.sh from a release mirror on the file
# system, then a project made and run on wasm, under a Node.js the installer
# fetched from nodejs.org.
#
#   tests/smoke-install.sh <directory holding ghul-cli-<rid>.tar.gz and its .sha256> <rid> <version>
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

archives="${1:?usage: tests/smoke-install.sh <archive directory> <rid> <version>}"
rid="${2:?a runtime identifier is needed}"
version="${3:?a version is needed}"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

fail() {
    echo "smoke-install: $*" >&2
    exit 1
}

mirror="$scratch/mirror"
tag="v$version"
mkdir -p "$mirror/download/$tag" "$mirror/api/releases"
cp "$archives/ghul-cli-$rid.tar.gz" "$archives/ghul-cli-$rid.tar.gz.sha256" "$mirror/download/$tag/"
printf '{"tag_name": "%s"}\n' "$tag" > "$mirror/api/releases/latest"

home="$scratch/home"
mkdir -p "$home"

# What a machine with no .NET has: the system tools, git for the libraries,
# and no node and no dotnet.
path_without_dotnet="/usr/bin:/bin:/usr/sbin:/sbin"

for hidden in dotnet node; do
    if env -i PATH="$path_without_dotnet" sh -c "command -v $hidden" > /dev/null 2>&1; then
        fail "$hidden is on the test's PATH, so the test would prove nothing"
    fi
done

run() {
    env -i HOME="$home" PATH="$home/.local/bin:$path_without_dotnet" \
        GHUL_CLI_API="file://$mirror/api" GHUL_CLI_RELEASES="file://$mirror/download" "$@"
}

echo "smoke-install: install.sh installs the archive and fetches Node.js..." >&2
run sh "$repo_root/install.sh" --version "$tag" --dir "$home/.local/opt/ghul" > "$scratch/install.out" 2>&1 \
    || { cat "$scratch/install.out" >&2; fail "install.sh failed"; }

cat "$scratch/install.out" >&2

[ -x "$home/.local/opt/ghul/ghul" ] || fail "the install left no executable"

reported="$(run ghul --version 2>&1 | head -n 1)"
echo "$reported" >&2
printf '%s' "$reported" | grep -q -- "$version" || fail "the installed tool reports '$reported'"

echo "smoke-install: a project is made and run on wasm..." >&2
mkdir -p "$scratch/work"
cd "$scratch/work"

run ghul new hello > "$scratch/new.out" 2>&1 || { cat "$scratch/new.out" >&2; fail "ghul new failed"; }
cd hello

out="$(run ghul run 2>"$scratch/run.err")" || { cat "$scratch/run.err" >&2; fail "ghul run failed"; }
cat "$scratch/run.err" >&2
echo "$out" >&2

printf '%s' "$out" | grep -qi 'hello' || fail "the program printed '$out'"

echo "smoke-install: passed" >&2
