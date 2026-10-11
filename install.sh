#!/bin/sh
#
# Installs ghul-cli, compiled with Native AOT, together with the compiler it
# ships beside it.
#
# Needs a POSIX shell, tar, and curl or wget. It needs nothing else: no .NET
# SDK, no .NET runtime, and no build tooling. What it installs is the same
# two things whether or not this machine ever had .NET on it.
#
#   curl -fsSL https://raw.githubusercontent.com/ghul-lang/ghul-cli/main/install.sh | sh
#
# Or, to see what it would do first:
#
#   sh install.sh --dry-run
#
# A machine that does have the SDK may prefer `dotnet tool install -g ghul.cli`,
# which is what gives the REPL and the Jupyter kernel - both of which host a
# session in this process and so need a .NET runtime. The REPL does not work
# in the AOT build, which is why this script installs the tool rather than the
# whole SDK.

set -eu

DEFAULT_VERSION="latest"
DEFAULT_ROOT="${HOME}/.local/opt/ghul"

REPOSITORY="ghul-lang/ghul-cli"

usage() {
    cat <<EOF
usage: install.sh [--version <tag>] [--dir <path>] [--dry-run] [--help]

  --version <tag>   the ghul-cli release to install, 'latest' by default
  --dir <path>      where to install it, ${DEFAULT_ROOT} by default
  --dry-run         report what would happen and install nothing
  --help            this text

Installing puts a directory on PATH if it is not already on it; the script
says which, and prints the line to add if you would rather do it yourself.

The tool goes to ~/.local/opt/ghul and the compiler it ships goes into the
ghul-cli cache (~/.cache/ghul-cli, or XDG_CACHE_HOME where that is set),
since that is where ghul-cli looks for it and where 'ghul cache clear'
clears it.
EOF
}

say() {
    printf '%s\n' "$*"
}

fail() {
    printf 'install.sh: %s\n' "$*" >&2
    exit 1
}

# --- arguments ---------------------------------------------------------------

version="${DEFAULT_VERSION}"
root="${DEFAULT_ROOT}"
dry_run="false"

while [ $# -gt 0 ]; do
    case "$1" in
        --version)
            [ $# -ge 2 ] || fail "--version needs a release tag"
            version="$2"
            shift 2
            ;;
        --version=*)
            version="${1#--version=}"
            shift
            ;;
        --dir)
            [ $# -ge 2 ] || fail "--dir needs a path"
            root="$2"
            shift 2
            ;;
        --dir=*)
            root="${1#--dir=}"
            shift
            ;;
        --dry-run)
            dry_run="true"
            shift
            ;;
        --help | -h)
            usage
            exit 0
            ;;
        *)
            usage >&2
            fail "unexpected argument: $1"
            ;;
    esac
done

# --- what we are, and what we are running on ----------------------------------

# Only the platform an archive is actually built for is offered. Saying so
# plainly beats installing something that will not run: the AOT builds are
# made per platform, because a binary built for one operating system is not
# a binary for another.
os="$(uname -s)"
machine="$(uname -m)"

case "${os}" in
    Linux) os_name="linux" ;;
    Darwin) os_name="osx" ;;
    *) fail "ghul-cli is not built for ${os}; install the .NET SDK and run 'dotnet tool install -g ghul.cli' instead" ;;
esac

case "${machine}" in
    x86_64 | amd64) arch_name="x64" ;;
    aarch64 | arm64) arch_name="arm64" ;;
    *) fail "ghul-cli is not built for ${machine} on ${os_name}" ;;
esac

rid="${os_name}-${arch_name}"

# --- how we fetch ------------------------------------------------------------

if command -v curl >/dev/null 2>&1; then
    fetch() { curl -fsSL "$1" -o "$2"; }
    fetch_to_stdout() { curl -fsSL "$1"; }
elif command -v wget >/dev/null 2>&1; then
    fetch() { wget -qO "$2" "$1"; }
    fetch_to_stdout() { wget -qO- "$1"; }
else
    fail "neither curl nor wget was found; one of them is needed to download ghul-cli"
fi

# sha256sum on Linux, shasum on macOS, which has no sha256sum.
if command -v sha256sum >/dev/null 2>&1; then
    checksum_of() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null 2>&1; then
    checksum_of() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
    fail "neither sha256sum nor shasum was found; one of them is needed to check the download"
fi

# --- which release -----------------------------------------------------------

# Where releases come from, named so a mirror - or a test - can serve them
# from elsewhere. The same shape as GHUL_COMPILER_FEED in the tool itself.
downloads="${GHUL_CLI_RELEASES:-https://github.com/${REPOSITORY}/releases/download}"
api="${GHUL_CLI_API:-https://api.github.com/repos/${REPOSITORY}}"

if [ "${version}" = "latest" ]; then
    say "looking up the latest ${REPOSITORY} release..."
    # The tag, read out of the release rather than parsed out of a header.
    body="$(fetch_to_stdout "${api}/releases/latest")" || fail "the latest release could not be read"
    # Split on the double quotes rather than matching them inside a quoted
    # string: a " inside "..." ends it, so a sed script written that way
    # unbalances the quoting.
    version=$(printf '%s' "${body}" | grep '"tag_name"' | head -n 1 | cut -d'"' -f4)

    if [ -z "${version}" ]; then
        fail "the latest release of ${REPOSITORY} could not be read"
    fi
fi

archive="ghul-cli-${rid}.tar.gz"
base="${downloads}/${version}"

# --- what we will do ---------------------------------------------------------

bin_dir="${HOME}/.local/bin"

say ""
say "ghul-cli ${version} (${rid})"
say "  install to  ${root}"
say "  link       ${bin_dir}/ghul"
say ""

if [ "${dry_run}" = "true" ]; then
    say "dry run; nothing installed. The archive would come from:"
    say "  ${base}/${archive}"
    exit 0
fi

# --- fetch and check ---------------------------------------------------------

work="$(mktemp -d 2>/dev/null || mktemp -d -t ghul-cli)" || fail "a temporary directory could not be made"

# Anything already downloaded into the work directory goes away with it, so an
# interrupted run leaves nothing of itself behind.
cleanup() {
    rm -rf "${work}"
}
trap cleanup EXIT INT TERM

say "downloading ${archive}..."
fetch "${base}/${archive}" "${work}/${archive}" || fail "the download failed; is ${version} a release of ${REPOSITORY}?"

if fetch "${base}/${archive}.sha256" "${work}/${archive}.sha256" 2>/dev/null; then
    expected="$(cut -d' ' -f1 < "${work}/${archive}.sha256")"
    actual="$(checksum_of "${work}/${archive}")"

    if [ "${expected}" != "${actual}" ]; then
        fail "the download is corrupt: expected sha256 ${expected}, got ${actual}"
    fi

    say "checked the download against the published sha256."
else
    say "no published sha256 for this asset; continuing without checking it."
fi

# The tool goes where a program goes; the compiler goes where the tool
# looks for it. It is not installed beside the executable because nothing
# here is installed - a manifest names the compiler a project wants and the
# tool fetches it into its cache - so the cache is where it belongs, and
# `ghul cache clear` clears it with everything else.
cache_home="${XDG_CACHE_HOME:-${HOME}/.cache}/ghul-cli"

# --- unpack ------------------------------------------------------------------

mkdir -p "${work}/unpack"
tar -xzf "${work}/${archive}" -C "${work}/unpack" || fail "the archive could not be unpacked"

if [ ! -x "${work}/unpack/ghul" ]; then
    fail "the archive holds no ghul executable at its root"
fi

if [ ! -d "${work}/unpack/compilers" ]; then
    fail "the archive holds no compilers directory beside ghul"
fi

# Checked before anything is replaced, so an archive with no compiler in it
# leaves the installed tool as it was.
shipped_any=""
for shipped in "${work}"/unpack/compilers/*; do
    [ -d "${shipped}" ] && shipped_any="true"
done

if [ -z "${shipped_any}" ]; then
    fail "the archive ships no compiler"
fi

# --- install -----------------------------------------------------------------

# Unpacked into a new directory and moved into place, so an install is either
# the old tool or the new one and never a half-written mixture of the two.
staged="${root}.new.$$"

rm -rf "${staged}"
mkdir -p "$(dirname "${root}")/$(basename "${staged}")"
mv "${work}/unpack/ghul" "${staged}/ghul" || fail "the tool could not be staged"

previous=""
if [ -d "${root}" ]; then
    previous="${root}.old.$$"
    mv "${root}" "${previous}" || fail "the installed tool could not be moved aside"
fi

if ! mv "${staged}" "${root}"; then
    # Put back what was there rather than leaving nothing at all.
    if [ -n "${previous}" ] && [ -d "${previous}" ]; then
        mv "${previous}" "${root}" || true
    fi

    fail "the tool could not be installed into ${root}"
fi

rm -rf "${previous}"

# --- put the compiler where the tool looks for it ----------------------------

seeded=""

for shipped in "${work}"/unpack/compilers/*; do
    [ -d "${shipped}" ] || continue

    version="$(basename "${shipped}")"
    target="${cache_home}/compilers/${version}"

    if [ -e "${target}" ]; then
        say "ghul.compiler ${version} is already in the cache; leaving it."
        continue
    fi

    mkdir -p "${target}"
    cp -R "${shipped}/." "${target}/" || fail "ghul.compiler ${version} could not be put in the cache"

    seeded="${seeded} ${version}"
done

# --- put it on PATH ----------------------------------------------------------

mkdir -p "${bin_dir}"

if [ -e "${bin_dir}/ghul" ] || [ -L "${bin_dir}/ghul" ]; then
    ln -sf "${root}/ghul" "${bin_dir}/ghul"
    say "relinked ${bin_dir}/ghul"
else
    ln -sf "${root}/ghul" "${bin_dir}/ghul"

    case ":${PATH}:" in
        *":${bin_dir}:"*) ;;
        *)
            say ""
            say "${bin_dir} is not on your PATH. Add this to your shell profile:"
            say ""
            say "    export PATH=\"${bin_dir}:\${PATH}\""
            ;;
    esac
fi

say ""
say "installed${seeded:+ ghul.compiler${seeded} into ${cache_home}/compilers}."
say ""
say "Try:"
say ""
say "    ghul --version"
say "    ghul new hello && cd hello && ghul run"