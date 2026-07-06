# HELIX Windows Installer

This folder contains the production Windows installer source for HELIX.

## Build Requirements

- Windows 10 or newer
- Python 3.11 or newer
- Internet access for Python package installation during build
- Inno Setup 6 installed from `https://jrsoftware.org/isinfo.php`

## Build Command

From the project root:

```powershell
powershell -ExecutionPolicy Bypass -File .\installer\build-installer.ps1
```

The final installer is written to:

```text
dist\installer\Install HELIX.exe
```

## Silent Install

```powershell
.\dist\installer\Install HELIX.exe /VERYSILENT /NORESTART
```

Enable startup launch during silent install:

```powershell
.\dist\installer\Install HELIX.exe /VERYSILENT /NORESTART /TASKS=launchstartup
```

## What The Installer Does

- Lets the user choose the installation directory, defaulting to `Program Files\HELIX`.
- Copies the bundled HELIX application.
- Installs Ollama silently when it is not already present.
- Starts Ollama and waits for `http://127.0.0.1:11434`.
- Pulls `qwen2.5:4b` with live Ollama progress, skipping it when already present.
- Creates Start Menu and optional desktop shortcuts.
- Adds the standard Windows uninstall entry.
- Optionally registers HELIX to launch on Windows startup.
- Launches HELIX automatically after Ollama is ready.

Installation logs are saved in:

```text
%ProgramData%\HELIX\logs
```
