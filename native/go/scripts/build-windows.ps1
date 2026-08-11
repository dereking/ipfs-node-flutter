#Requires -Version 5.1
<#
.SYNOPSIS
    One-click Windows build for the native IPFS node core.

.DESCRIPTION
    Ensures a mingw-w64 gcc toolchain (downloading a portable build on demand),
    then compiles the Go native core into dist\ipfs_node_core.dll, packages the
    C ABI header, and optionally runs the Go tests and the example Windows app.

    Run everything:
        powershell -ExecutionPolicy Bypass -File scripts\build-windows.ps1 -Example

.PARAMETER Example
    Also build the example Windows app (flutter build windows --release), which
    embeds the freshly built DLL next to the executable.

.PARAMETER Test
    Run the Go core tests before building.

.PARAMETER MingwUrl
    URL of a portable mingw-w64 build (zip) used when no gcc is on PATH.
    Defaults to the latest WinLibs x86_64-posix-seh release.

.PARAMETER ToolsDir
    Directory used to cache the portable mingw-w64 toolchain. Defaults to
    %LOCALAPPDATA%\ipfs-node-flutter-tools so the repository stays clean.
#>
[CmdletBinding()]
param(
    [switch]$Example,
    [switch]$Test,
    [string]$MingwUrl = 'https://github.com/brechtsanders/winlibs_mingw/releases/download/16.2.0posix-14.0.0-ucrt-r1/winlibs-x86_64-posix-seh-gcc-16.2.0-mingw-w64ucrt-14.0.0-r1.zip',
    [string]$ToolsDir = ''
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$goDir    = Join-Path $repoRoot 'native\go'
$distDir  = Join-Path $goDir 'dist'

function Write-Step([string]$message) {
    Write-Host "==> $message" -ForegroundColor Cyan
}

function Find-InPath([string]$name) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Resolve-MingwGcc {
    $existing = Find-InPath 'gcc'
    if ($existing) {
        Write-Step "Using gcc from PATH: $existing"
        return $existing
    }

    if ([string]::IsNullOrWhiteSpace($ToolsDir)) {
        $ToolsDir = Join-Path $env:LOCALAPPDATA 'ipfs-node-flutter-tools'
    }
    $gccPath = Join-Path $ToolsDir 'mingw64\bin\gcc.exe'
    if (Test-Path $gccPath) {
        Write-Step "Using cached portable mingw-w64 gcc: $gccPath"
        return $gccPath
    }

    Write-Step "mingw-w64 gcc not found on PATH; downloading portable toolchain..."
    New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
    $zip = Join-Path $ToolsDir 'mingw64.zip'
    Invoke-WebRequest -Uri $MingwUrl -OutFile $zip -UseBasicParsing
    try {
        Expand-Archive -Path $zip -DestinationPath $ToolsDir -Force
    } finally {
        Remove-Item $zip -ErrorAction SilentlyContinue
    }
    if (-not (Test-Path $gccPath)) {
        throw "Portable toolchain did not install gcc at expected path: $gccPath"
    }
    Write-Step "Downloaded portable mingw-w64 gcc: $gccPath"
    return $gccPath
}

function Package-AbiHeader([string]$header) {
    $generated = "$header.generated"
    Move-Item -Force -Path $header -Destination $generated
    try {
        $lines = @(Get-Content -Path $generated)
        $required = @(
            'extern uintptr_t ipfs_node_create(void);',
            'extern int ipfs_node_start(uintptr_t handle, char* request);',
            'extern int ipfs_node_stop(uintptr_t handle);',
            'extern char* ipfs_node_status(uintptr_t handle);',
            'extern char* ipfs_node_capabilities(uintptr_t handle);',
            'extern char* ipfs_node_get_block(uintptr_t handle, char* cid, int timeout_millis);',
            'extern void ipfs_node_free(uintptr_t handle);',
            'extern void ipfs_node_free_string(char* value);'
        )
        foreach ($declaration in $required) {
            if ($lines -notcontains $declaration) {
                throw "generated C ABI header is missing: $declaration"
            }
        }
        $body = @($lines | ForEach-Object { ' ' + $_ })
        $prelude = @(
            '/* Packaged IPFS node C ABI. Generated declarations follow. */',
            '#ifndef IPFS_NODE_CORE_H',
            '#define IPFS_NODE_CORE_H',
            '',
            '/* Stable return codes for ipfs_node_start and ipfs_node_stop. */',
            '#define IPFS_NODE_OK 0',
            '#define IPFS_NODE_ERR_INVALID_HANDLE 1',
            '#define IPFS_NODE_ERR_INVALID_CONFIGURATION 2',
            '#define IPFS_NODE_ERR_INVALID_STATE 3',
            '#define IPFS_NODE_ERR_NODE_ALREADY_RUNNING 4',
            ''
        )
        $postlude = @(
            '',
            '#endif /* IPFS_NODE_CORE_H */'
        )
        $content = ($prelude + $body + $postlude) -join "`r`n"
        Set-Content -Path $header -Value $content -Encoding ascii
    } finally {
        Remove-Item $generated -ErrorAction SilentlyContinue
    }
}

$go = Find-InPath 'go'
if (-not $go) {
    throw 'Go toolchain not found on PATH. Install Go from https://go.dev/dl/'
}
Write-Step "Using Go: $go"

$gcc = Resolve-MingwGcc
$env:CC = $gcc

Push-Location $goDir
try {
    $env:GOOS = 'windows'
    $env:CGO_ENABLED = '1'

    if ($Test) {
        Write-Step 'Running Go core tests...'
        & go test ./internal/core/ -count=1
        if ($LASTEXITCODE -ne 0) { throw 'Go core tests failed.' }
    }

    New-Item -ItemType Directory -Force -Path $distDir | Out-Null
    Write-Step 'Building ipfs_node_core.dll...'
    & go build -buildmode=c-shared -o (Join-Path $distDir 'ipfs_node_core.dll') ./cmd/ipfs_node_core
    if ($LASTEXITCODE -ne 0) { throw 'go build failed.' }

    Write-Step 'Packaging C ABI header...'
    Package-AbiHeader -header (Join-Path $distDir 'ipfs_node_core.h')
} finally {
    Pop-Location
    Remove-Item Env:GOOS -ErrorAction SilentlyContinue
    Remove-Item Env:CGO_ENABLED -ErrorAction SilentlyContinue
}

$dll = Join-Path $distDir 'ipfs_node_core.dll'
$header = Join-Path $distDir 'ipfs_node_core.h'
if (-not (Test-Path $dll) -or -not (Test-Path $header)) {
    throw "Build did not produce $dll / $header"
}
Write-Host ''
Write-Host "Built native IPFS node core:" -ForegroundColor Green
Write-Host "  $dll"
Write-Host "  $header"

if ($Example) {
    Write-Step 'Building the example Windows app (flutter build windows --release)...'
    Push-Location (Join-Path $repoRoot 'example')
    try {
        & flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw 'flutter build windows failed.' }
    } finally {
        Pop-Location
    }
    Write-Host ''
    Write-Host 'Example app built; the DLL is bundled next to the executable.' -ForegroundColor Green
}

Write-Host ''
Write-Host 'Done.' -ForegroundColor Green
