#Requires -Version 5.1
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallDir,
    [string]$LaunchAtStartup = "0",
    [switch]$Silent
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$ModelName = "qwen2.5:4b"
$OllamaDownloadUrl = "https://ollama.com/download/OllamaSetup.exe"
$LogDir = Join-Path $env:ProgramData "HELIX\logs"
$LogPath = Join-Path $LogDir "install.log"

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
Start-Transcript -Path $LogPath -Append | Out-Null

function Write-HelixLine {
    param([string]$Message, [ConsoleColor]$Color = [ConsoleColor]::Gray)
    Write-Host $Message -ForegroundColor $Color
}

function Write-Step {
    param([int]$Number, [string]$Message)
    Write-HelixLine ""
    Write-HelixLine ("[{0}/8] {1}" -f $Number, $Message) Cyan
}

function Complete-Step {
    param([string]$Message = "OK")
    Write-HelixLine ("OK - {0}" -f $Message) Green
}

function Fail-Install {
    param([string]$Message)
    Write-HelixLine ""
    Write-HelixLine ("Installation failed: {0}" -f $Message) Red
    Write-HelixLine ("Log file: {0}" -f $LogPath) Yellow
    Stop-Transcript | Out-Null
    if (-not $Silent) {
        Read-Host "Press Enter to close this window"
    }
    exit 1
}

function Get-FreeBytes {
    param([string]$Path)
    $root = [System.IO.Path]::GetPathRoot((Resolve-Path -LiteralPath $Path).Path)
    $drive = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $root.TrimEnd('\'))
    return [int64]$drive.FreeSpace
}

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

function Start-Ollama {
    param([string]$OllamaExe)
    $service = Get-Service -Name "Ollama" -ErrorAction SilentlyContinue
    if ($service) {
        if ($service.Status -ne "Running") {
            Start-Service -Name "Ollama"
        }
        return
    }

    $existing = Get-Process -Name "ollama" -ErrorAction SilentlyContinue
    if (-not $existing) {
        Start-Process -FilePath $OllamaExe -ArgumentList "serve" -WindowStyle Hidden | Out-Null
    }
}

function Wait-OllamaReady {
    param([int]$TimeoutSeconds = 120)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        try {
            $response = Invoke-WebRequest -Uri "http://127.0.0.1:11434/api/tags" -UseBasicParsing -TimeoutSec 3
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) { return $true }
        } catch {
            Start-Sleep -Seconds 2
        }
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Test-OllamaModel {
    param([string]$OllamaExe, [string]$Name)
    $models = & $OllamaExe list 2>$null
    if ($LASTEXITCODE -ne 0) { return $false }
    return ($models -match ("^{0}\s" -f [regex]::Escape($Name)))
}

try {
    Clear-Host
    Write-HelixLine "HELIX Installer v1.0" White
    Write-HelixLine ("Install directory: {0}" -f $InstallDir) DarkGray
    Write-HelixLine ("Log file: {0}" -f $LogPath) DarkGray

    Write-Step 1 "Checking Windows version..."
    $os = Get-CimInstance Win32_OperatingSystem
    $build = [int]$os.BuildNumber
    if ($build -lt 10240) {
        Fail-Install "HELIX requires Windows 10 or newer."
    }
    $freeBytes = Get-FreeBytes -Path $InstallDir
    if ($freeBytes -lt 12GB) {
        Fail-Install "At least 12 GB of free disk space is required for HELIX, Ollama, and qwen2.5:4b."
    }
    Complete-Step ("Windows {0}, {1:N1} GB free" -f $os.Caption, ($freeBytes / 1GB))

    Write-Step 2 "Installing Ollama..."
    $ollamaExe = Find-OllamaExe
    if ($ollamaExe) {
        Complete-Step ("Existing Ollama detected at {0}" -f $ollamaExe)
    } else {
        $installerPath = Join-Path $env:TEMP "OllamaSetup.exe"
        Write-HelixLine "Downloading Ollama..."
        try {
            Invoke-WebRequest -Uri $OllamaDownloadUrl -OutFile $installerPath -UseBasicParsing
        } catch {
            Fail-Install "Could not download Ollama. Check your Internet connection and run the installer again."
        }

        Write-HelixLine "Running Ollama installer silently..."
        $proc = Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait -PassThru
        if ($proc.ExitCode -ne 0) {
            Fail-Install ("Ollama installer returned exit code {0}." -f $proc.ExitCode)
        }
        Start-Sleep -Seconds 3
        $ollamaExe = Find-OllamaExe
        if (-not $ollamaExe) {
            Fail-Install "Ollama installed, but ollama.exe could not be found."
        }
        Complete-Step "Ollama installed"
    }

    Write-Step 3 "Starting Ollama..."
    Start-Ollama -OllamaExe $ollamaExe
    if (-not (Wait-OllamaReady -TimeoutSeconds 120)) {
        Fail-Install "Ollama did not respond on http://127.0.0.1:11434."
    }
    Complete-Step "Running"

    Write-Step 4 "Downloading AI model..."
    if (Test-OllamaModel -OllamaExe $ollamaExe -Name $ModelName) {
        Complete-Step ("{0} already exists" -f $ModelName)
    } else {
        Write-HelixLine ("Pulling {0}..." -f $ModelName)
        & $ollamaExe pull $ModelName
        if ($LASTEXITCODE -ne 0) {
            Fail-Install ("Model download failed or was interrupted. Run the installer again to resume pulling {0}." -f $ModelName)
        }
        Complete-Step "Complete"
    }

    Write-Step 5 "Installing HELIX..."
    $helixExe = Join-Path $InstallDir "HELIX.exe"
    if (-not (Test-Path -LiteralPath $helixExe)) {
        Fail-Install "HELIX.exe was not copied into the installation directory."
    }
    $dataDir = Join-Path $env:USERPROFILE ".helix\data"
    New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
    Complete-Step "Application files ready"

    Write-Step 6 "Creating shortcuts..."
    $desktopShortcut = Join-Path ([Environment]::GetFolderPath("Desktop")) "HELIX.lnk"
    $startMenuShortcut = Join-Path ([Environment]::GetFolderPath("Programs")) "HELIX\HELIX.lnk"
    if ((Test-Path -LiteralPath $desktopShortcut) -or (Test-Path -LiteralPath $startMenuShortcut)) {
        Complete-Step "Shortcuts registered"
    } else {
        Complete-Step "Shortcuts will be available from the Start Menu"
    }

    Write-Step 7 "Registering startup..."
    $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    if ($LaunchAtStartup -eq "1") {
        New-Item -Path $runKey -Force | Out-Null
        Set-ItemProperty -Path $runKey -Name "HELIX" -Value ('"{0}"' -f $helixExe)
        Complete-Step "HELIX will launch when Windows starts"
    } else {
        Remove-ItemProperty -Path $runKey -Name "HELIX" -ErrorAction SilentlyContinue
        Complete-Step "Startup launch not enabled"
    }

    Write-Step 8 "Launching HELIX..."
    if (-not (Wait-OllamaReady -TimeoutSeconds 120)) {
        Fail-Install "Ollama stopped responding before HELIX could launch."
    }
    Start-Process -FilePath $helixExe -WorkingDirectory $InstallDir | Out-Null
    Complete-Step "HELIX launched"

    Write-HelixLine ""
    Write-HelixLine "Installation Complete" Green
    Stop-Transcript | Out-Null
    if (-not $Silent) {
        Start-Sleep -Seconds 2
    }
    exit 0
} catch {
    Fail-Install $_.Exception.Message
}
