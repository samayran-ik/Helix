#Requires -Version 5.1
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallDir,
    [string]$RemoveModels = "0"
)

$ErrorActionPreference = "Continue"
$LogDir = Join-Path $env:ProgramData "HELIX\logs"
$LogPath = Join-Path $LogDir "uninstall.log"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
Start-Transcript -Path $LogPath -Append | Out-Null

function Find-OllamaExe {
    $cmd = Get-Command ollama.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Ollama\ollama.exe"),
        (Join-Path $env:LOCALAPPDATA "Ollama\ollama.exe"),
        (Join-Path $env:ProgramFiles "Ollama\ollama.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Ollama\ollama.exe")
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    if ($candidates.Count -gt 0) { return $candidates[0] }
    return $null
}

try {
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "HELIX" -ErrorAction SilentlyContinue

    Get-Process -Name "HELIX" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    if ($RemoveModels -eq "1") {
        $ollamaExe = Find-OllamaExe
        if ($ollamaExe) {
            & $ollamaExe rm "qwen2.5:4b"
        }
    }
} finally {
    Stop-Transcript | Out-Null
}
