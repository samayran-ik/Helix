#Requires -Version 5.1
param(
    [string]$InnoSetupCompiler
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -Path $ProjectRoot

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host ("==> {0}" -f $Message) -ForegroundColor Cyan
}

function Fail {
    param([string]$Message)
    Write-Host ""
    Write-Host ("ERROR: {0}" -f $Message) -ForegroundColor Red
    exit 1
}

function Find-InnoCompiler {
    param([string]$ExplicitPath)
    if ($ExplicitPath) {
        if (Test-Path -LiteralPath $ExplicitPath) { return (Resolve-Path -LiteralPath $ExplicitPath).Path }
        Fail ("Inno Setup compiler was not found at {0}" -f $ExplicitPath)
    }

    $cmd = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"),
        (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe")
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    if ($candidates.Count -gt 0) { return $candidates[0] }
    Fail "Inno Setup 6 compiler (ISCC.exe) was not found. Install Inno Setup 6, then run this build again."
}

Write-Step "Building HELIX portable application"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\build-windows-portable.ps1"
if ($LASTEXITCODE -ne 0) { Fail "Portable HELIX build failed." }

$helixExe = Join-Path $ProjectRoot "dist\HELIX\HELIX.exe"
if (-not (Test-Path -LiteralPath $helixExe)) {
    Fail "Expected dist\HELIX\HELIX.exe was not produced."
}

Write-Step "Compiling Windows installer"
$iscc = Find-InnoCompiler -ExplicitPath $InnoSetupCompiler
& "$iscc" ".\installer\HELIX.iss"
if ($LASTEXITCODE -ne 0) { Fail "Inno Setup failed to compile the installer." }

$installer = Join-Path $ProjectRoot "dist\installer\Install HELIX.exe"
if (-not (Test-Path -LiteralPath $installer)) {
    Fail "Expected installer was not produced."
}

Write-Host ""
Write-Host "Build complete." -ForegroundColor Green
Write-Host ("Installer: {0}" -f $installer) -ForegroundColor Green
