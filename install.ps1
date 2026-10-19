# Installs ghul-cli on Windows, compiled with Native AOT. The compiler is not
# part of it: the first build fetches one.
#
# Needs Windows PowerShell 5.1 or PowerShell 7, which every supported Windows
# has. It needs nothing else: no .NET SDK, no .NET runtime and no build
# tooling.
#
#   irm https://raw.githubusercontent.com/ghul-lang/ghul-cli/main/install.ps1 | iex
#
# Or, to see what it would do first:
#
#   .\install.ps1 --dry-run
#
# The arguments are the ones install.sh takes, written with either one or two
# dashes: --version <tag>, --dir <path>, --no-node, --dry-run and --help.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repository = 'ghul-lang/ghul-cli'

function Say([string] $text) {
    Write-Host $text
}

function Fail([string] $text) {
    [Console]::Error.WriteLine("install.ps1: $text")
    exit 1
}

function Usage {
    Say 'usage: install.ps1 [--version <tag>] [--dir <path>] [--no-node] [--dry-run] [--help]'
    Say ''
    Say '  --version <tag>   the ghul-cli release to install, latest by default'
    Say '  --dir <path>      where to install it, %LOCALAPPDATA%\ghul by default'
    Say '  --no-node         do not fetch Node.js where none is found on PATH'
    Say '  --dry-run         report what would happen and install nothing'
    Say '  --help            this text'
    Say ''
    Say 'The tool goes to %LOCALAPPDATA%\ghul, which is added to your PATH. It ships'
    Say 'no compiler: the first build fetches one into the ghul-cli cache, where'
    Say "'ghul cache clear' clears it, and 'ghul update' keeps it current."
}

# --- arguments ---------------------------------------------------------------

$version = 'latest'
$root = Join-Path $env:LOCALAPPDATA 'ghul'
$wantNode = $true
$dryRun = $false

$i = 0
while ($i -lt $args.Count) {
    $name = ([string] $args[$i]).TrimStart('-').ToLowerInvariant()

    switch ($name) {
        'version' {
            if ($i + 1 -ge $args.Count) { Fail '--version needs a release tag' }
            $version = [string] $args[$i + 1]
            $i += 2
        }
        'dir' {
            if ($i + 1 -ge $args.Count) { Fail '--dir needs a path' }
            $root = [string] $args[$i + 1]
            $i += 2
        }
        'no-node' { $wantNode = $false; $i += 1 }
        'nonode' { $wantNode = $false; $i += 1 }
        'dry-run' { $dryRun = $true; $i += 1 }
        'dryrun' { $dryRun = $true; $i += 1 }
        'help' { Usage; exit 0 }
        'h' { Usage; exit 0 }
        default {
            Usage
            Fail "unexpected argument: $($args[$i])"
        }
    }
}

# --- what we are running on ---------------------------------------------------

if ($env:OS -ne 'Windows_NT') {
    Fail 'this installer is for Windows; on Linux and macOS use install.sh'
}

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()

switch ($architecture) {
    'X64' { $rid = 'win-x64' }
    'Arm64' { $rid = 'win-arm64' }
    default { Fail "ghul-cli is not built for Windows on $architecture; install the .NET SDK and run 'dotnet tool install -g ghul.cli' instead" }
}

# --- how we fetch ------------------------------------------------------------

# Where releases come from, named so a mirror, or a test, can serve them from
# elsewhere. A file:// mirror is read from the file system, which
# Invoke-WebRequest cannot do.
$downloads = if ($env:GHUL_CLI_RELEASES) { $env:GHUL_CLI_RELEASES } else { "https://github.com/$repository/releases/download" }
$api = if ($env:GHUL_CLI_API) { $env:GHUL_CLI_API } else { "https://api.github.com/repos/$repository" }

function Fetch([string] $url, [string] $destination) {
    if ($url.StartsWith('file://')) {
        $path = ([System.Uri] $url).LocalPath

        if (-not (Test-Path $path)) { throw "$url does not exist" }

        Copy-Item -LiteralPath $path -Destination $destination
        return
    }

    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $destination -Headers @{ 'User-Agent' = 'ghul-cli-install' }
}

function FetchText([string] $url) {
    $scratch = [System.IO.Path]::GetTempFileName()

    try {
        Fetch $url $scratch
        return [System.IO.File]::ReadAllText($scratch)
    } finally {
        Remove-Item -LiteralPath $scratch -Force -ErrorAction SilentlyContinue
    }
}

# --- which release -----------------------------------------------------------

if ($version -eq 'latest') {
    Say "looking up the latest $repository release..."

    try {
        $body = FetchText "$api/releases/latest"
        $version = ($body | ConvertFrom-Json).tag_name
    } catch {
        Fail 'the latest release could not be read'
    }

    if (-not $version) { Fail "the latest release of $repository could not be read" }
}

$archive = "ghul-cli-$rid.zip"
$base = "$downloads/$version"

Say ''
Say "ghul-cli $version ($rid)"
Say "  install to  $root"
Say ''

if ($dryRun) {
    Say 'dry run; nothing installed. The archive would come from:'
    Say "  $base/$archive"
    exit 0
}

# --- fetch and check ---------------------------------------------------------

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("ghul-cli-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null

try {
    $zip = Join-Path $work $archive

    Say "downloading $archive..."

    try {
        Fetch "$base/$archive" $zip
    } catch {
        Fail "the download failed; is $version a release of $repository for $rid?"
    }

    $published = Join-Path $work "$archive.sha256"
    $haveSum = $true

    try {
        Fetch "$base/$archive.sha256" $published
    } catch {
        $haveSum = $false
    }

    if ($haveSum) {
        $expected = (([System.IO.File]::ReadAllText($published)).Trim() -split '\s+')[0].ToLowerInvariant()
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash.ToLowerInvariant()

        if ($expected -ne $actual) {
            Fail "the download is corrupt: expected sha256 $expected, got $actual"
        }

        Say 'checked the download against the published sha256.'
    } else {
        Say 'no published sha256 for this asset; continuing without checking it.'
    }

    # --- unpack --------------------------------------------------------------

    $unpacked = Join-Path $work 'unpack'

    Expand-Archive -LiteralPath $zip -DestinationPath $unpacked -Force

    $fresh = Join-Path $unpacked 'ghul.exe'

    if (-not (Test-Path $fresh)) { Fail 'the archive holds no ghul.exe at its root' }

    # --- install -------------------------------------------------------------

    # A running executable can be renamed but not overwritten or deleted, and
    # the tool being updated is the one running this script. So the old
    # ghul.exe is renamed aside, the new one put in its place, and the old one
    # removed once it can be: now if nothing runs it, and on the next install
    # otherwise.
    New-Item -ItemType Directory -Path $root -Force | Out-Null

    $target = Join-Path $root 'ghul.exe'
    $aside = $null

    if (Test-Path $target) {
        $aside = Join-Path $root ("ghul.old." + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.exe')
        Move-Item -LiteralPath $target -Destination $aside
    }

    try {
        Copy-Item -LiteralPath $fresh -Destination $target
    } catch {
        if ($aside -and (Test-Path $aside)) { Move-Item -LiteralPath $aside -Destination $target -Force }

        Fail "the tool could not be installed into $root"
    }

    Get-ChildItem -LiteralPath $root -Filter 'ghul.old.*.exe' -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }

    # --- put it on PATH ------------------------------------------------------

    $normalised = $root.TrimEnd('\')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = if ($userPath) { $userPath -split ';' | Where-Object { $_ } } else { @() }
    $onPath = $entries | Where-Object { $_.TrimEnd('\') -ieq $normalised }

    if (-not $onPath) {
        $joined = if ($userPath) { "$userPath;$normalised" } else { $normalised }
        [Environment]::SetEnvironmentVariable('Path', $joined, 'User')
        Say ''
        Say "added $normalised to your PATH; open a new terminal to use ghul."
    }

    if (-not (($env:Path -split ';') | Where-Object { $_.TrimEnd('\') -ieq $normalised })) {
        $env:Path = "$env:Path;$normalised"
    }

    # --- Node.js -------------------------------------------------------------

    # ghul runs its compiler and wasm programs with Node.js and fetches one on
    # first use where none runs the wasm target. Fetching it here as well
    # means the first build does not wait for it.
    if ($wantNode -and -not (Get-Command node -ErrorAction SilentlyContinue)) {
        Say ''
        Say 'ghul runs its compiler and wasm programs with Node.js, and none was found.'

        $fetched = Start-Process -FilePath $target -ArgumentList 'install', 'node' -NoNewWindow -Wait -PassThru
        $code = $fetched.ExitCode

        if ($code -ne 0) {
            Say "Node.js could not be fetched; 'ghul install node' brings one in later."
        }
    }

    Say ''
    Say 'Try:'
    Say ''
    Say '    ghul --version'
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
