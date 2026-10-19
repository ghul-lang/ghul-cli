# End-to-end test of `ghul update` on Windows, against a release mirror on the
# file system. The mirror carries two releases of the executable under test:
# one under the tag of the version it reports, one under a newer tag. The
# executable is installed from the mirror with install.ps1, then asked to
# update itself, which replaces the running ghul.exe.
#
#   tests/update.ps1 <path to the Native AOT ghul.exe> <rid>
param(
    [Parameter(Mandatory = $true)] [string] $Executable,
    [Parameter(Mandatory = $true)] [string] $Rid
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("ghul-update-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null

function Fail([string] $text) {
    Write-Host "update: $text"
    exit 1
}

$running = ((& $Executable version | Select-Object -First 1) -split ' ')[1]
$running = ($running -split '\+')[0]
$newer = '99.0.0'

$mirror = Join-Path $scratch 'mirror'
New-Item -ItemType Directory -Path (Join-Path $mirror 'api/releases') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $mirror 'feed/ghul.compiler') -Force | Out-Null
Set-Content -Path (Join-Path $mirror 'feed/ghul.compiler/index.json') -Value '{"versions": ["0.0.0"]}'

$mirrorUrl = 'file:///' + ($mirror -replace '\\', '/')
$home_ = Join-Path $scratch 'home'
New-Item -ItemType Directory -Path (Join-Path $home_ 'AppData\Local') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $home_ 'AppData\Roaming') -Force | Out-Null

$env:USERPROFILE = $home_
$env:HOME = $home_
$env:LOCALAPPDATA = Join-Path $home_ 'AppData\Local'
$env:APPDATA = Join-Path $home_ 'AppData\Roaming'
$env:GHUL_CLI_API = "$mirrorUrl/api"
$env:GHUL_CLI_RELEASES = "$mirrorUrl/download"
$env:GHUL_COMPILER_FEED = "$mirrorUrl/feed"

function Release([string] $tag) {
    $releaseDir = Join-Path $mirror "download/$tag"
    $payload = Join-Path $scratch "payload-$tag"

    New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null
    New-Item -ItemType Directory -Path $payload -Force | Out-Null
    Copy-Item $Executable (Join-Path $payload 'ghul.exe')

    $zip = Join-Path $releaseDir "ghul-cli-$Rid.zip"
    Compress-Archive -Path (Join-Path $payload 'ghul.exe') -DestinationPath $zip

    $sum = (Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash.ToLowerInvariant()
    Set-Content -Path "$zip.sha256" -Value "$sum  ghul-cli-$Rid.zip"

    $script = Join-Path $releaseDir 'ghul-cli-install.ps1'
    Copy-Item (Join-Path $repoRoot 'install.ps1') $script
    $scriptSum = (Get-FileHash -Algorithm SHA256 -LiteralPath $script).Hash.ToLowerInvariant()
    Set-Content -Path "$script.sha256" -Value "$scriptSum  ghul-cli-install.ps1"
}

function Latest([string] $tag) {
    Set-Content -Path (Join-Path $mirror 'api/releases/latest') -Value ('{"tag_name": "' + $tag + '"}')
}

Release "v$running"
Release "v$newer"

$root = Join-Path $home_ 'AppData\Local\ghul'

Write-Host "update: installing ghul $running from the mirror..."
Latest "v$running"
$out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'install.ps1') --version "v$running" --no-node 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { Write-Host $out; Fail 'install.ps1 could not install the executable under test' }

$installed = Join-Path $root 'ghul.exe'
if (-not (Test-Path $installed)) { Fail 'install.ps1 left no ghul.exe' }

Write-Host 'update: an install that is the latest says so...'
$out = & $installed update --check 2>&1 | Out-String
if ($out -notmatch 'is the latest release') { Fail "expected --check to report the latest, got: $out" }

Write-Host 'update: --check reports a newer release and changes nothing...'
Latest "v$newer"
$out = & $installed update --check 2>&1 | Out-String
if ($out -notmatch "v$newer is the latest release") { Fail "expected --check to name v$newer, got: $out" }

Write-Host 'update: a newer release replaces the running ghul.exe...'
$out = & $installed update 2>&1 | Out-String
Write-Host $out
if ($LASTEXITCODE -ne 0) { Fail "'ghul update' failed" }
if ($out -notmatch "updating ghul $([regex]::Escape($running)) to v$newer") { Fail "expected the update to say what it did, got: $out" }

$after = (& $installed version | Select-Object -First 1)
if (-not $after) { Fail 'the updated ghul.exe does not run' }

Write-Host "update: passed ($after)"
