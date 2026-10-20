# Installs the Native AOT archive the way a user does and uses it, with nothing
# of .NET on the machine's PATH: install.ps1 from a release mirror on the file
# system, then a project made and run on wasm, under a Node.js the installer
# fetched from nodejs.org.
#
#   tests/smoke-install.ps1 <directory holding ghul-cli-<rid>.zip and its .sha256> <rid> <version>
param(
    [Parameter(Mandatory = $true)] [string] $Archives,
    [Parameter(Mandatory = $true)] [string] $Rid,
    [Parameter(Mandatory = $true)] [string] $Version
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("ghul-smoke-install-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null

function Fail([string] $text) {
    Write-Host "smoke-install: $text"
    exit 1
}

$tag = "v$Version"
$mirror = Join-Path $scratch 'mirror'
New-Item -ItemType Directory -Path (Join-Path $mirror "download/$tag") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $mirror 'api/releases') -Force | Out-Null

Copy-Item (Join-Path $Archives "ghul-cli-$Rid.zip") (Join-Path $mirror "download/$tag/")
Copy-Item (Join-Path $Archives "ghul-cli-$Rid.zip.sha256") (Join-Path $mirror "download/$tag/")
Set-Content -Path (Join-Path $mirror 'api/releases/latest') -Value ('{"tag_name": "' + $tag + '"}')

# What a machine with no .NET has: the system, and git for the libraries. No
# node and no dotnet; the installer fetches Node.js.
$systemRoot = $env:SystemRoot
$git = Join-Path $env:ProgramFiles 'Git\cmd'
$cleanPath = "$systemRoot\System32;$systemRoot;$systemRoot\System32\WindowsPowerShell\v1.0;$git"

$home_ = Join-Path $scratch 'home'
$installDir = Join-Path $scratch 'ghul'
New-Item -ItemType Directory -Path $home_ | Out-Null

# A child process with that environment and nothing else of this one's.
function Run([string] $file, [string[]] $arguments, [string] $directory) {
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $file
    foreach ($argument in $arguments) { $start.ArgumentList.Add($argument) }
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.WorkingDirectory = $directory
    $start.Environment.Clear()
    $start.Environment['SystemRoot'] = $systemRoot
    $start.Environment['SYSTEMDRIVE'] = $env:SystemDrive
    $start.Environment['OS'] = 'Windows_NT'
    $start.Environment['PATH'] = $cleanPath
    $start.Environment['USERPROFILE'] = $home_
    $start.Environment['LOCALAPPDATA'] = Join-Path $home_ 'AppData\Local'
    $start.Environment['APPDATA'] = Join-Path $home_ 'AppData\Roaming'
    $start.Environment['TEMP'] = Join-Path $home_ 'Temp'
    $start.Environment['TMP'] = Join-Path $home_ 'Temp'
    $start.Environment['HOME'] = $home_
    $start.Environment['GHUL_CLI_API'] = "file:///" + ($mirror -replace '\\', '/') + "/api"
    $start.Environment['GHUL_CLI_RELEASES'] = "file:///" + ($mirror -replace '\\', '/') + "/download"

    $process = [System.Diagnostics.Process]::Start($start)
    $out = $process.StandardOutput.ReadToEndAsync()
    $err = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()

    return @{ Code = $process.ExitCode; Out = $out.Result; Err = $err.Result }
}

New-Item -ItemType Directory -Path (Join-Path $home_ 'AppData\Local') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $home_ 'AppData\Roaming') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $home_ 'Temp') -Force | Out-Null

foreach ($hidden in 'dotnet', 'node') {
    $found = Run 'cmd.exe' @('/c', "where $hidden") $scratch

    if ($found.Code -eq 0) { Fail "$hidden is on the test's PATH, so the test would prove nothing: $($found.Out)" }
}

Write-Host 'smoke-install: install.ps1 installs the archive and fetches Node.js...'
$powershell = Join-Path $systemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$installed = Run $powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $repoRoot 'install.ps1'), '--version', $tag, '--dir', $installDir) $scratch
Write-Host $installed.Out
Write-Host $installed.Err

if ($installed.Code -ne 0) { Fail 'install.ps1 failed' }

$ghul = Join-Path $installDir 'ghul.exe'

if (-not (Test-Path $ghul)) { Fail 'the install left no ghul.exe' }

$reported = Run $ghul @('--version') $scratch
Write-Host $reported.Out

if (($reported.Out + $reported.Err) -notmatch [regex]::Escape($Version)) { Fail "the installed tool reports '$($reported.Out)'" }

Write-Host 'smoke-install: a project is made and run on wasm...'
$work = Join-Path $scratch 'work'
New-Item -ItemType Directory -Path $work | Out-Null

$made = Run $ghul @('new', 'hello') $work
Write-Host $made.Out
Write-Host $made.Err

if ($made.Code -ne 0) { Fail 'ghul new failed' }

$ran = Run $ghul @('run') (Join-Path $work 'hello')
Write-Host $ran.Out
Write-Host $ran.Err

if ($ran.Code -ne 0) { Fail 'ghul run failed' }
if ($ran.Out -notmatch 'hello') { Fail "the program printed '$($ran.Out)'" }

Write-Host 'smoke-install: passed'
