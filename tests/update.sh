#!/usr/bin/env bash
# End-to-end test of `ghul update`, against a release mirror on the file
# system. It needs the Native AOT build, since that is the only build
# install.sh installs and the only one `ghul update` updates:
#
#   tests/update.sh <path to the Native AOT ghul executable>
#
# The mirror carries two releases. One holds the executable under test, under
# the tag of the version it reports; the other is a newer release whose ghul
# is a stub that prints its version. The executable is installed from the
# mirror with the repository's own install.sh, then asked to update itself.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

aot="${1:?usage: tests/update.sh <path to the Native AOT ghul executable>}"
aot="$(cd "$(dirname "$aot")" && pwd)/$(basename "$aot")"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

fail() {
    echo "update: $*" >&2
    exit 1
}

case "$(uname -m)" in
    aarch64 | arm64) rid="linux-arm64" ;;
    *) rid="linux-x64" ;;
esac

running="$("$aot" version | head -n 1 | cut -d' ' -f2)"
running="${running%%+*}"
newer="99.0.0"

mirror="$scratch/mirror"
mkdir -p "$mirror/api/releases" "$mirror/download" "$mirror/feed/ghul.compiler"

export HOME="$scratch/home"
export XDG_CACHE_HOME="$scratch/cache"
export GHUL_CLI_API="file://$mirror/api"
export GHUL_CLI_RELEASES="file://$mirror/download"
# The component sweep `ghul update` runs reads the compiler feed; pointed at
# the mirror it stays off the network, and the one version it lists is the
# one the releases below ship, so nothing is ever stale.
export GHUL_COMPILER_FEED="file://$mirror/feed"
printf '{"versions": ["0.0.0"]}\n' > "$mirror/feed/ghul.compiler/index.json"
mkdir -p "$HOME"

# A release directory holding `ghul`, packed and checksummed
# the way the release job packs them.
release() {
    local tag="$1" executable="$2" release_dir="$mirror/download/$1" payload="$scratch/payload-$1"

    mkdir -p "$release_dir" "$payload"
    cp "$executable" "$payload/ghul"
    chmod +x "$payload/ghul"

    tar -czf "$release_dir/ghul-cli-$rid.tar.gz" -C "$payload" ghul
    cp "$repo_root/install.sh" "$release_dir/ghul-cli-install.sh"

    (
        cd "$release_dir"
        sha256sum "ghul-cli-$rid.tar.gz" > "ghul-cli-$rid.tar.gz.sha256"
        sha256sum ghul-cli-install.sh > ghul-cli-install.sh.sha256
    )
}

latest() {
    printf '{"tag_name": "%s"}\n' "$1" > "$mirror/api/releases/latest"
}

stub="$scratch/stub-ghul"
cat > "$stub" <<EOF
#!/bin/sh
echo "ghul $newer"
EOF

release "v$running" "$aot"
release "v$newer" "$stub"

root="$HOME/.local/opt/ghul"

echo "update: installing ghul $running from the mirror..." >&2
latest "v$running"
sh "$repo_root/install.sh" --version "v$running" > "$scratch/install.out" 2>&1 || {
    cat "$scratch/install.out" >&2
    fail "install.sh could not install the executable under test"
}

installed="$root/ghul"

echo "update: an install that is the latest says so..." >&2
out="$("$installed" update --check 2>&1)" || fail "'ghul update --check' failed: $out"
grep -q "is the latest release" <<< "$out" || fail "expected --check to report the latest, got: $out"

out="$("$installed" update 2>&1)" || fail "'ghul update' failed: $out"
grep -q "is the latest release" <<< "$out" || fail "expected update to report the latest, got: $out"

out="$("$installed" update --version "v$running" 2>&1)" || fail "'ghul update --version' failed: $out"
grep -q "which is v$running" <<< "$out" || fail "expected --version of the running release to say so, got: $out"

latest "v$newer"

echo "update: --check reports a newer release and changes nothing..." >&2
out="$("$installed" update --check 2>&1)" || fail "'ghul update --check' failed: $out"
grep -q "v$newer is the latest release" <<< "$out" || fail "expected --check to name v$newer, got: $out"
"$installed" version | grep -q "ghul $running" || fail "--check changed the installed tool"

echo "update: a checksum mismatch fails and leaves the tool as it was..." >&2
good_checksum="$(cat "$mirror/download/v$newer/ghul-cli-install.sh.sha256")"
echo "0000000000000000000000000000000000000000000000000000000000000000  ghul-cli-install.sh" \
    > "$mirror/download/v$newer/ghul-cli-install.sh.sha256"

if out="$("$installed" update 2>&1)"; then
    fail "expected a checksum mismatch to fail, got: $out"
fi

grep -q "does not match its published sha256" <<< "$out" || fail "expected the mismatch to be named, got: $out"
"$installed" version | grep -q "ghul $running" || fail "a failed update changed the installed tool"

echo "$good_checksum" > "$mirror/download/v$newer/ghul-cli-install.sh.sha256"

echo "update: an update installs the newer release..." >&2
out="$("$installed" update 2>"$scratch/update.err")" || fail "'ghul update' failed: $(cat "$scratch/update.err")"
[ -z "$out" ] || fail "'ghul update' wrote to stdout, which is kept for a script's output: $out"
"$installed" version | grep -q "ghul $newer" || fail "expected ghul $newer after the update, got: $("$installed" version)"

[ "$(ls -A "$root")" = "ghul" ] || fail "the install root holds more than ghul after the update: $(ls -A "$root")"

echo "update: all checks passed." >&2
