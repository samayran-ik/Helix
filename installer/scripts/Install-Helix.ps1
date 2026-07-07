#Requires -Version 5.1
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallDir,
    [string]$LaunchAtStartup = "0",
    [switch]$Silent
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Log folder and file setup
$LogDir = Join-Path $env:ProgramData "HELIX\logs"
$LogPath = Join-Path $LogDir "install.log"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
Start-Transcript -Path $LogPath -Append | Out-Null

# Encoding-safe Character Codes for GUI Icons (escaped as chars to support ANSI/locale parsing)
$IconPending = [char]0x25CB # White circle '○'
$IconLoading = [char]0x25B6 # Black right triangle '▶'
$IconSuccess = [char]0x2713 # Checkmark '✔'
$IconError   = [char]0x2717 # Ballot X '✘'
$IconSail    = [char]0x26F5 # Sailboat '⛵'

# Global Installation state variables
$ModelName = "qwen2.5:4b"
$global:PythonExePath = ""
$global:PythonNeedsInstall = $true
$global:PythonInstallerPath = ""
$global:OllamaExePath = ""
$global:OllamaInstallerPath = ""
$global:OllamaStartedByUs = $false
$global:InstallationCancelled = $false
$global:CurrentRunningTaskIndex = 0

# Step estimates for remaining time calculations (in seconds)
$StepEstimates = @{
    "admin"        = 1
    "internet"     = 1
    "python_check" = 2
    "python_dl"    = 25
    "python_inst"  = 40
    "python_ver"   = 2
    "ollama_inst"  = 30
    "ollama_svc"   = 5
    "model_pull"   = 75
    "pip_deps"     = 45
    "shortcuts"    = 5
}

# Helpers
function Write-Log ($Message) {
    $timestamp = (Get-Date).ToString("HH:mm:ss")
    $logLine = "[{0}] {1}" -f $timestamp, $Message
    Write-Output $logLine
    if ($LogBox) {
        $LogBox.Dispatcher.Invoke([Action]{
            $LogBox.AppendText($logLine + "`r`n")
            $LogBox.ScrollToEnd()
        })
    }
}

# Pre-load assemblies for WPF
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase | Out-Null

# WPF XAML Definition
$XAML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2000/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2000/xaml"
        Title="HELIX Installation" Height="620" Width="680" Background="#000000"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize" WindowStyle="None" BorderThickness="1" BorderBrush="#222222">
    <Window.Resources>
        <Style TargetType="TextBlock">
            <Setter Property="FontFamily" Value="Segoe UI, Arial"/>
            <Setter Property="Foreground" Value="#ffffff"/>
        </Style>
    </Window.Resources>
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="60"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <!-- Header Bar -->
        <Border Grid.Row="0" Background="#050505" BorderBrush="#222222" BorderThickness="0,0,0,1" Name="HeaderBar">
            <Grid Margin="15,0">
                <TextBlock Name="HeaderTitle" Text="H E L I X  S E T U P" FontSize="15" FontWeight="Bold" VerticalAlignment="Center" Foreground="#ffffff"/>
                <Button Name="CloseButton" Content="✕" HorizontalAlignment="Right" VerticalAlignment="Center" Width="30" Height="30" Background="Transparent" Foreground="#888888" BorderThickness="0" FontSize="16" Cursor="Hand"/>
            </Grid>
        </Border>
        
        <!-- Title and Progress Info -->
        <StackPanel Grid.Row="1" Margin="25,20,25,10">
            <TextBlock Name="TitleText" Text="Configuring Helix..." FontSize="22" FontWeight="Light" Margin="0,0,0,5"/>
            <TextBlock Name="SubtitleText" Text="Preparing your personal AI workspace." FontSize="12" Foreground="#888888" Margin="0,0,0,15"/>
            
            <Grid Margin="0,0,0,5">
                <TextBlock Name="TaskText" Text="Initializing setup steps..." FontSize="12" Foreground="#cccccc" HorizontalAlignment="Left"/>
                <TextBlock Name="PercentText" Text="0%" FontSize="12" FontWeight="SemiBold" HorizontalAlignment="Right"/>
            </Grid>
            <ProgressBar Name="ProgressBar" Height="8" Background="#111111" Foreground="#ffffff" BorderThickness="0" Minimum="0" Maximum="100" Value="0" Margin="0,0,0,5"/>
            <TextBlock Name="TimeText" Text="Estimated time remaining: Calculating..." FontSize="11" Foreground="#555555"/>
        </StackPanel>
        
        <!-- Main Panel: Steps ScrollViewer & Collapsible Logs -->
        <Grid Grid.Row="2" Margin="25,10,25,10">
            <Grid.RowDefinitions>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            
            <!-- Steps Container -->
            <ScrollViewer Grid.Row="0" VerticalScrollBarVisibility="Auto" Margin="0,0,0,10">
                <StackPanel Name="StepsContainer" Margin="5"/>
            </ScrollViewer>
            
            <!-- Collapsible Logs Bar -->
            <Grid Grid.Row="1" Name="LogHeader" Margin="0,5,0,5" Cursor="Hand" Background="#080808">
                <TextBlock Text="Detailed Log Viewer" FontSize="11" Foreground="#888888" HorizontalAlignment="Left" VerticalAlignment="Center" Margin="5,3"/>
                <TextBlock Name="LogToggleIcon" Text="[+] Show Logs" FontSize="11" Foreground="#888888" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="5,3"/>
            </Grid>
            
            <!-- Logs Area -->
            <TextBox Grid.Row="2" Name="LogBox" Height="140" Background="#020202" Foreground="#00ff00" BorderBrush="#222222" BorderThickness="1" 
                     FontFamily="Consolas" FontSize="11" IsReadOnly="True" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap" Margin="0,0,0,10" Visibility="Collapsed"/>
        </Grid>
        
        <!-- Bottom Action Bar -->
        <Border Grid.Row="3" Background="#050505" BorderBrush="#222222" BorderThickness="0,1,0,0" Padding="15">
            <Grid>
                <TextBlock Name="StatusFooter" Text="Production Installer v1.0.2" FontSize="11" Foreground="#555555" VerticalAlignment="Center" HorizontalAlignment="Left"/>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                    <Button Name="RetryButton" Content="Retry" Width="80" Height="28" Background="#111111" Foreground="#ffffff" BorderBrush="#333333" Margin="0,0,10,0" Visibility="Collapsed" Cursor="Hand"/>
                    <Button Name="ActionButton" Content="Cancel" Width="80" Height="28" Background="#000000" Foreground="#ffffff" BorderBrush="#222222" Cursor="Hand"/>
                </StackPanel>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

# Helper to force UI redraw & handle events
function Update-UI {
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{}, 'Background')
}

# Version comparison helper
function Compare-Versions ($v1, $v2) {
    [version]$ver1 = $v1
    [version]$ver2 = $v2
    return $ver1.CompareTo($ver2)
}

# Resolve standard paths for executable search
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

# Ollama server runner
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

# API readiness check
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

# Model check
function Test-ModelExists ($OllamaExe, $Name) {
    try {
        $models = & $OllamaExe list 2>$null
        if ($LASTEXITCODE -eq 0) {
            return ($models -match ("^{0}\s" -f [regex]::Escape($Name)))
        }
    } catch {}
    return $false
}

# Locates python in system or user registries
function Find-Python {
    $py = Get-Command python -ErrorAction SilentlyContinue
    if ($py) {
        $path = $py.Source
        try {
            $out = & $path -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>$null
            if ($out -and (Compare-Versions $out.Trim() "3.11" -ge 0)) {
                return @{ Path = $path; Version = $out.Trim() }
            }
        } catch {}
    }

    $roots = @(
        "HKLM:\SOFTWARE\Python\PythonCore",
        "HKCU:\SOFTWARE\Python\PythonCore",
        "HKLM:\SOFTWARE\Wow6432Node\Python\PythonCore",
        "HKCU:\SOFTWARE\Wow6432Node\Python\PythonCore"
    )
    
    foreach ($root in $roots) {
        if (Test-Path $root) {
            $versions = Get-ChildItem $root | Select-Object -ExpandProperty PSChildName
            foreach ($v in $versions) {
                if ($v -match '^3\.(\d+)') {
                    $minor = [int]$Matches[1]
                    if ($minor -ge 11) {
                        $ipPath = Join-Path $root "$v\InstallPath"
                        if (Test-Path $ipPath) {
                            $dir = Get-ItemPropertyValue -Path $ipPath -Name ""
                            $exe = Join-Path $dir "python.exe"
                            if (Test-Path $exe) {
                                return @{ Path = $exe; Version = $v }
                            }
                        }
                    }
                }
            }
        }
    }
    return $null
}

# Verification script
function Verify-PythonEnv {
    Reload-Path
    
    $pythonVersion = ""
    $pipVersion = ""
    try {
        if ($global:PythonExePath) {
            $pythonVersion = & $global:PythonExePath --version 2>&1
            $pipVersion = & $global:PythonExePath -m pip --version 2>&1
        } else {
            $pythonVersion = & python --version 2>&1
            $pipVersion = & pip --version 2>&1
        }
    } catch {
        return $false
    }
    
    Write-Log "Verifying dynamic Python dependencies:"
    Write-Log "Python command: $pythonVersion"
    Write-Log "Pip command: $pipVersion"
    
    if (-not $pythonVersion -or -not $pipVersion) {
        return $false
    }
    return $true
}

# Reload Environment PATH variables dynamically
function Reload-Path {
    Write-Log "Synchronizing environment variables and PATH..."
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    
    # Prepend dynamic python registration paths to prevent script termination
    $roots = @("HKLM:\SOFTWARE\Python\PythonCore", "HKCU:\SOFTWARE\Python\PythonCore")
    foreach ($root in $roots) {
        if (Test-Path $root) {
            $versions = Get-ChildItem $root | Select-Object -ExpandProperty PSChildName
            foreach ($v in $versions) {
                $ipPath = Join-Path $root "$v\InstallPath"
                if (Test-Path $ipPath) {
                    $dir = Get-ItemPropertyValue -Path $ipPath -Name ""
                    $exe = Join-Path $dir "python.exe"
                    $scripts = Join-Path $dir "Scripts"
                    if (Test-Path $exe) {
                        if ($env:Path -notlike "*$dir*") {
                            $env:Path = "$dir;$scripts;$env:Path"
                            Write-Log "Added registry path to session environment: $dir"
                        }
                    }
                }
            }
        }
    }
}

# Scrape python.org Windows download index for stable x64 installers
function Get-Latest-Python-Url {
    Write-Log "Scraping python.org for newest stable release URL..."
    $html = Invoke-RestMethod -Uri "https://www.python.org/downloads/windows/" -UseBasicParsing
    $pattern = 'https://www\.python\.org/ftp/python/3\.\d+\.\d+/python-3\.\d+\.\d+-amd64\.exe'
    $matches = [regex]::Matches($html, $pattern)
    
    if ($matches.Count -eq 0) {
        $pattern = 'https://www\.python\.org/ftp/python/3\.[^"/]+?/python-3\.[^"/]+?-amd64\.exe'
        $matches = [regex]::Matches($html, $pattern)
    }
    
    $stableUrls = @()
    foreach ($m in $matches) {
        $url = $m.Value
        if ($url -notmatch '(a|b|rc)\d') { # exclude pre-releases
            $stableUrls += $url
        }
    }
    
    if ($stableUrls.Count -gt 0) {
        return $stableUrls[0]
    }
    throw "Unable to dynamically fetch stable Python installer URL. Please check connection."
}

# Download file with progress updates to WPF UI
function Download-WithProgress ($Url, $LocalPath, $StepName) {
    Write-Log "Initializing transfer: $Url"
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
    
    $wc.add_DownloadProgressChanged({
        param($sender, $e)
        if ($ProgressBar -and $PercentText -and $TaskText) {
            $ProgressBar.Value = $e.ProgressPercentage
            $PercentText.Text = "$($e.ProgressPercentage)%"
            $TaskText.Text = "Downloading ($($e.ProgressPercentage)%): $StepName"
            Update-UI
        }
    })
    
    $wc.DownloadFileAsync($Url, $LocalPath)
    while ($wc.IsBusy) {
        Start-Sleep -Milliseconds 50
        Update-UI
        if ($global:InstallationCancelled) {
            $wc.CancelAsync()
            throw "Installation cancelled by user."
        }
    }
    Write-Log "Transfer completed."
}

# Stream local Ollama pull progress with percentage calculations
function Pull-Model ($ModelName) {
    Write-Log "Requesting download of model $ModelName from local server..."
    $uri = "http://127.0.0.1:11434/api/pull"
    
    $request = [System.Net.HttpWebRequest]::Create($uri)
    $request.Method = "POST"
    $request.ContentType = "application/json"
    $request.Timeout = 1800000 # 30 minutes
    
    $streamWriter = New-Object System.IO.StreamWriter($request.GetRequestStream())
    $streamWriter.Write('{"name":"' + $ModelName + '"}')
    $streamWriter.Flush()
    $streamWriter.Close()
    
    $response = $request.GetResponse()
    $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
    
    while (-not $reader.EndOfStream) {
        $line = $reader.ReadLine()
        if ($line) {
            try {
                $json = ConvertFrom-Json $line -ErrorAction SilentlyContinue
                if ($json) {
                    if ($json.total -gt 0) {
                        $pct = [math]::Round(($json.completed / $json.total) * 100)
                        if ($ProgressBar -and $PercentText -and $TaskText) {
                            $ProgressBar.Value = $pct
                            $PercentText.Text = "$pct%"
                            $TaskText.Text = "Pulling AI model: $pct% ($($json.status))"
                            Update-UI
                        }
                    } else {
                        if ($TaskText) {
                            $TaskText.Text = "Pulling AI model: $($json.status)"
                            Update-UI
                        }
                    }
                }
            } catch {}
        }
        if ($global:InstallationCancelled) {
            $response.Close()
            throw "Installation cancelled by user."
        }
    }
    $response.Close()
    Write-Log "Model pull complete."
}

# Setup WPF Step elements dynamically
function Set-StepUIState ($Name, $State, $Details = "") {
    if ($Silent) { return }
    $StepsContainer.Dispatcher.Invoke([Action]{
        $tb = $StepsContainer.FindName("step_" + $Name)
        if ($tb) {
            switch ($State) {
                "pending" {
                    $tb.Text = $IconPending + " " + $tb.Tag
                    $tb.Foreground = [System.Windows.Media.Brushes]::Gray
                }
                "loading" {
                    $tb.Text = $IconLoading + " " + $tb.Tag + "..."
                    $tb.Foreground = [System.Windows.Media.Brushes]::White
                }
                "success" {
                    $tb.Text = $IconSuccess + " " + $tb.Tag
                    $tb.Foreground = [System.Windows.Media.Brushes]::Green
                }
                "error" {
                    $tb.Text = $IconError + " " + $tb.Tag + " (Failed)"
                    $tb.Foreground = [System.Windows.Media.Brushes]::Red
                }
            }
        }
    })
    Update-UI
}

# Task actions definition
$TaskActions = @{
    "admin" = {
        Write-Log "Verifying administrator permissions..."
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw "Administrator permission is mandatory to perform machine-wide setups."
        }
        Write-Log "Administrator permission verified."
    }
    "internet" = {
        Write-Log "Verifying Internet connectivity..."
        try {
            $ips = [System.Net.Dns]::GetHostAddresses("www.python.org")
            if ($ips.Length -eq 0) { throw "DNS verification failed" }
            Write-Log "Internet connectivity confirmed."
        } catch {
            throw "Internet connection is required to fetch installer resources."
        }
    }
    "python_check" = {
        Write-Log "Checking for existing local Python installation >= 3.11..."
        $py = Find-Python
        if ($py) {
            $global:PythonExePath = $py.Path
            $global:PythonNeedsInstall = $false
            Write-Log "Compatible Python installation detected: $($py.Version) at $($py.Path)"
        } else {
            $global:PythonNeedsInstall = $true
            Write-Log "No compatible Python >= 3.11 found on system registry or Path."
        }
    }
    "python_dl" = {
        if (-not $global:PythonNeedsInstall) {
            Write-Log "Skipping Python download: system matches standard version."
            return
        }
        $url = Get-Latest-Python-Url
        $global:PythonInstallerPath = Join-Path $env:TEMP "python-installer.exe"
        Download-WithProgress -Url $url -LocalPath $global:PythonInstallerPath -StepName "Python Release Bundle"
    }
    "python_inst" = {
        if (-not $global:PythonNeedsInstall) {
            Write-Log "Skipping Python silent install: system matches standard version."
            return
        }
        Write-Log "Running dynamic stable Python installer silently..."
        $proc = Start-Process -FilePath $global:PythonInstallerPath -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_pip=1 Include_launcher=1 InstallLauncherAllUsers=1 DisableMaxPath=1" -Wait -PassThru
        if ($proc.ExitCode -ne 0) {
            throw "Python installation failed with executable error code $($proc.ExitCode)"
        }
        Write-Log "Python installation complete. Cleaning up installer binary..."
        Remove-Item -Path $global:PythonInstallerPath -ErrorAction SilentlyContinue
    }
    "python_ver" = {
        Write-Log "Running installation validation checks..."
        $ok = Verify-PythonEnv
        if (-not $ok) {
            throw "Python verification checks failed. Path did not update or pip is inaccessible."
        }
        $py = Find-Python
        if ($py) {
            $global:PythonExePath = $py.Path
        } else {
            $global:PythonExePath = "python"
        }
        Write-Log "Python environment verified successfully."
    }
    "ollama_inst" = {
        Write-Log "Checking for Ollama installation..."
        $ollamaExe = Find-OllamaExe
        if ($ollamaExe) {
            $global:OllamaExePath = $ollamaExe
            Write-Log "Existing Ollama binary detected: $ollamaExe"
            return
        }
        
        Write-Log "Ollama not detected. Fetching latest installer..."
        $url = "https://ollama.com/download/OllamaSetup.exe"
        $global:OllamaInstallerPath = Join-Path $env:TEMP "OllamaSetup.exe"
        Download-WithProgress -Url $url -LocalPath $global:OllamaInstallerPath -StepName "Ollama Setup"
        
        Write-Log "Executing Ollama setup silently..."
        $proc = Start-Process -FilePath $global:OllamaInstallerPath -ArgumentList "/S" -Wait -PassThru
        if ($proc.ExitCode -ne 0) {
            throw "Ollama installer exited with code $($proc.ExitCode)"
        }
        
        Remove-Item -Path $global:OllamaInstallerPath -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        
        $ollamaExe = Find-OllamaExe
        if (-not $ollamaExe) {
            throw "Ollama installation completed but executable is not found."
        }
        $global:OllamaExePath = $ollamaExe
        $global:OllamaStartedByUs = $true
        Write-Log "Ollama silently configured."
    }
    "ollama_svc" = {
        Write-Log "Asserting Ollama service daemon state..."
        Start-Ollama -OllamaExe $global:OllamaExePath
        if (-not (Wait-OllamaReady -TimeoutSeconds 120)) {
            throw "Ollama server did not respond at port 11434 after startup."
        }
        Write-Log "Ollama background service running."
    }
    "model_pull" = {
        Write-Log "Checking local Ollama model registry for $ModelName..."
        if (Test-ModelExists -OllamaExe $global:OllamaExePath -Name $ModelName) {
            Write-Log "Model $ModelName is already present in registry. Skipping pull."
            return
        }
        Pull-Model -ModelName $ModelName
    }
    "pip_deps" = {
        $reqFile = Join-Path $InstallDir "requirements.txt"
        $reqOptFile = Join-Path $InstallDir "requirements-optional.txt"
        
        if (Test-Path $reqFile) {
            Write-Log "Provisioning dynamic Python dependencies from requirements.txt..."
            $proc = Start-Process -FilePath $global:PythonExePath -ArgumentList "-m pip install --upgrade pip" -Wait -NoNewWindow -PassThru
            $proc = Start-Process -FilePath $global:PythonExePath -ArgumentList "-m pip install -r `"$reqFile`"" -Wait -NoNewWindow -PassThru
            if ($proc.ExitCode -ne 0) {
                throw "Pip core dependency installation failed with code $($proc.ExitCode)"
            }
        }
        
        if (Test-Path $reqOptFile) {
            Write-Log "Provisioning dynamic optional dependencies from requirements-optional.txt..."
            $proc = Start-Process -FilePath $global:PythonExePath -ArgumentList "-m pip install -r `"$reqOptFile`"" -Wait -NoNewWindow -PassThru
            if ($proc.ExitCode -ne 0) {
                throw "Pip optional dependency installation failed with code $($proc.ExitCode)"
            }
        }
        Write-Log "System python packages provisioned."
    }
    "shortcuts" = {
        Write-Log "Setting up environment launchers and shortcuts..."
        $helixExe = Join-Path $InstallDir "HELIX.exe"
        if (-not (Test-Path $helixExe)) {
            throw "HELIX.exe was not found in $InstallDir"
        }
        
        # Configure Startup registry key
        $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
        if ($LaunchAtStartup -eq "1") {
            New-Item -Path $runKey -Force | Out-Null
            Set-ItemProperty -Path $runKey -Name "HELIX" -Value ('"{0}"' -f $helixExe)
            Write-Log "Registered autostart key."
        } else {
            Remove-ItemProperty -Path $runKey -Name "HELIX" -ErrorAction SilentlyContinue
        }
        
        # Start HELIX application
        Write-Log "Launching background services and launcher tray icon..."
        Start-Process -FilePath $helixExe -WorkingDirectory $InstallDir | Out-Null
        Write-Log "Shortcuts and startup launch ready."
    }
}

# Run tasks sequentially
function Run-InstallEngine {
    $totalSteps = $Steps.Count
    
    for ($i = $global:CurrentRunningTaskIndex; $i -lt $totalSteps; $i++) {
        if ($global:InstallationCancelled) { break }
        
        $step = $Steps[$i]
        $global:CurrentRunningTaskIndex = $i
        
        # Update progress labels
        $taskName = $step.Name
        $taskText = $step.Text
        Write-Log "---------------------------------------------"
        Write-Log "Executing step [$($i+1)/$totalSteps]: $taskText"
        
        if ($PercentText -and $ProgressBar) {
            $currentPct = [math]::Round(($i / $totalSteps) * 100)
            $ProgressBar.Value = $currentPct
            $PercentText.Text = "$currentPct%"
            $TaskText.Text = "Running: $taskText"
        }
        
        # Recalculate remaining time
        if ($TimeText) {
            $remainingSec = 0
            for ($j = $i; $j -lt $totalSteps; $j++) {
                $remainingSec += $StepEstimates[$Steps[$j].Name]
            }
            $min = [math]::Floor($remainingSec / 60)
            $sec = $remainingSec % 60
            if ($min -gt 0) {
                $TimeText.Text = "Estimated time remaining: ~$min minutes $sec seconds"
            } else {
                $TimeText.Text = "Estimated time remaining: ~$sec seconds"
            }
        }
        
        Set-StepUIState -Name $taskName -State "loading"
        
        # Run action with failure recovery
        try {
            $action = $TaskActions[$taskName]
            & $action
            Set-StepUIState -Name $taskName -State "success"
        } catch {
            Write-Log "ERROR occurred at step '$taskName': $_"
            Set-StepUIState -Name $taskName -State "error"
            
            if ($Silent) {
                # Silent installations must fail immediately
                Write-Error "Silent install failed at step $($taskName): $_"
                Stop-Transcript | Out-Null
                exit 1
            } else {
                # Handle GUI retry/failure dialog
                Handle-FailureRecovery -ErrorMsg $_.Exception.Message
                return # Pause execution
            }
        }
    }
    
    # Complete
    if (-not $global:InstallationCancelled -and $global:CurrentRunningTaskIndex -eq $totalSteps - 1) {
        Write-Log "============================================="
        Write-Log "Helix installation completed successfully."
        if ($ProgressBar -and $PercentText -and $TaskText -and $TitleText -and $ActionButton) {
            $ProgressBar.Value = 100
            $PercentText.Text = "100%"
            $TitleText.Text = "Installation Complete"
            $TaskText.Text = "Helix is ready to sail!"
            $ActionButton.Content = "Finish"
            $TimeText.Text = ""
        }
    }
}

# Failure recovery GUI behavior
function Handle-FailureRecovery ($ErrorMsg) {
    $TitleText.Dispatcher.Invoke([Action]{
        $TitleText.Text = "Setup Encountered an Error"
        $SubtitleText.Text = $ErrorMsg
        $TaskText.Text = "Waiting for user action..."
        $PercentText.Text = "--%"
        
        # Display Retry button and focus ActionButton to Cancel
        $RetryButton.Visibility = 'Visible'
        $ActionButton.Content = "Cancel"
    })
}

# Run headless installation for silent tasks
function Run-Silent-Install {
    Write-Log "Running silent automated installer..."
    $global:CurrentRunningTaskIndex = 0
    $totalSteps = $Steps.Count
    
    for ($i = 0; $i -lt $totalSteps; $i++) {
        $step = $Steps[$i]
        $taskName = $step.Name
        $taskText = $step.Text
        Write-Host "Running [$($i+1)/$totalSteps]: $taskText..." -ForegroundColor Cyan
        try {
            $action = $TaskActions[$taskName]
            & $action
            Write-Host "Success." -ForegroundColor Green
        } catch {
            Write-Error "Task '$taskName' failed: $_"
            Rollback-Install
            exit 1
        }
    }
    Write-Host "Silent installation complete." -ForegroundColor Green
}

# Standard Rollback Operation
function Rollback-Install {
    Write-Log "Running rollback safety actions..."
    if ($global:PythonInstallerPath -and (Test-Path $global:PythonInstallerPath)) {
        Remove-Item -Path $global:PythonInstallerPath -ErrorAction SilentlyContinue
    }
    if ($global:OllamaInstallerPath -and (Test-Path $global:OllamaInstallerPath)) {
        Remove-Item -Path $global:OllamaInstallerPath -ErrorAction SilentlyContinue
    }
    if ($global:OllamaStartedByUs) {
        Write-Log "Stopping local Ollama process..."
        Stop-Process -Name "ollama" -ErrorAction SilentlyContinue
    }
    Write-Log "Rollback complete."
}

# Steps list mapping
$Steps = @(
    @{ Name = "admin"; Text = "Checking Administrator Permission" },
    @{ Name = "internet"; Text = "Checking Internet Connection" },
    @{ Name = "python_check"; Text = "Checking Python Environment" },
    @{ Name = "python_dl"; Text = "Downloading Python Installer" },
    @{ Name = "python_inst"; Text = "Installing Python Silently" },
    @{ Name = "python_ver"; Text = "Verifying Python Installation" },
    @{ Name = "ollama_inst"; Text = "Installing Ollama Silently" },
    @{ Name = "ollama_svc"; Text = "Starting Ollama Service" },
    @{ Name = "model_pull"; Text = "Pulling AI Model (qwen2.5:4b)" },
    @{ Name = "pip_deps"; Text = "Installing Python Dependencies" },
    @{ Name = "shortcuts"; Text = "Configuring Shortcuts & Startup" }
)

# Start installation execution
if ($Silent) {
    Run-Silent-Install
    Stop-Transcript | Out-Null
    exit 0
}

# --- GUI Setup and Thread launching ---
try {
    Write-Log "Initializing Installer GUI Window..."
    $xml = [xml]$XAML
    $reader = New-Object System.Xml.XmlNodeReader($xml)
    $window = [Windows.Markup.XamlReader]::Load($reader)
    
    # Locate UI Controls
    $ProgressBar = $window.FindName("ProgressBar")
    $PercentText = $window.FindName("PercentText")
    $TaskText = $window.FindName("TaskText")
    $TitleText = $window.FindName("TitleText")
    $SubtitleText = $window.FindName("SubtitleText")
    $TimeText = $window.FindName("TimeText")
    $LogToggleIcon = $window.FindName("LogToggleIcon")
    $LogBox = $window.FindName("LogBox")
    $LogHeader = $window.FindName("LogHeader")
    $StepsContainer = $window.FindName("StepsContainer")
    $ActionButton = $window.FindName("ActionButton")
    $RetryButton = $window.FindName("RetryButton")
    $HeaderBar = $window.FindName("HeaderBar")
    $CloseButton = $window.FindName("CloseButton")
    $HeaderTitle = $window.FindName("HeaderTitle")
    
    # Set safe unicode icon in title dynamically
    $HeaderTitle.Text = $IconSail + " H E L I X  S E T U P"
    
    # Wire Drag Window Event
    $HeaderBar.Add_MouseLeftButtonDown({
        $window.DragMove()
    })
    
    # Wire Close Button
    $CloseButton.Add_Click({
        $global:InstallationCancelled = $true
        $window.Close()
    })
    
    # Wire Action Button
    $ActionButton.Add_Click({
        if ($ActionButton.Content -eq "Finish") {
            $window.Close()
        } else {
            $global:InstallationCancelled = $true
            $window.Close()
        }
    })
    
    # Wire Retry Button
    $RetryButton.Add_Click({
        $RetryButton.Visibility = 'Collapsed'
        $ActionButton.Content = "Cancel"
        $TitleText.Text = "Configuring Helix..."
        $SubtitleText.Text = "Preparing your personal AI workspace."
        # Reset current step state and resume
        Set-StepUIState -Name $Steps[$global:CurrentRunningTaskIndex].Name -State "pending"
        
        # Async invoke install resume to let dispatcher process button click
        $window.Dispatcher.BeginInvoke([Action]{
            Run-InstallEngine
        })
    })
    
    # Wire Collapsible Logs Panel
    $LogHeader.Add_MouseDown({
        if ($LogBox.Visibility -eq 'Collapsed') {
            $LogBox.Visibility = 'Visible'
            $LogToggleIcon.Text = "[-] Hide Logs"
            $window.Height = 770
        } else {
            $LogBox.Visibility = 'Collapsed'
            $LogToggleIcon.Text = "[+] Show Logs"
            $window.Height = 620
        }
    })
    
    # Create the Steps list dynamically in the UI
    foreach ($step in $Steps) {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Name = "step_" + $step.Name
        $tb.Tag = $step.Text
        $tb.Text = $IconPending + " " + $step.Text
        $tb.FontSize = 13
        $tb.Margin = New-Object System.Windows.Thickness(10, 4, 0, 4)
        $tb.Foreground = [System.Windows.Media.Brushes]::Gray
        
        # Explicitly register name in WPF namespace so FindName works later
        $window.RegisterName($tb.Name, $tb)
        $StepsContainer.Children.Add($tb) | Out-Null
    }
    
    # Wire ContentRendered to begin installation
    $window.Add_ContentRendered({
        # Run the installer loop on the dispatcher thread asynchronously
        $window.Dispatcher.BeginInvoke([Action]{
            Run-InstallEngine
        })
    })
    
    # Run the WPF UI
    $window.ShowDialog() | Out-Null
    
} catch {
    Write-Log "CRITICAL SETUP ERROR: $_"
    if (-not $Silent) {
        [System.Windows.MessageBox]::Show("Helix Installation Failed: $_", "Setup Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    }
} finally {
    if ($global:InstallationCancelled -or $global:CurrentRunningTaskIndex -lt $Steps.Count - 1) {
        Rollback-Install
    }
    Stop-Transcript | Out-Null
}
