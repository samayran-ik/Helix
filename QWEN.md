# Helix Project Instructions

## Environment

- Operating System: Windows 11
- Shell: PowerShell
- Never assume Linux.
- Never use bash syntax.

## Shell Commands

Use ONLY PowerShell commands.

Correct:
- Get-ChildItem
- Get-Content
- Select-String
- Test-Path
- Copy-Item
- Move-Item
- Remove-Item
- Invoke-WebRequest

Never use:
- ls
- grep
- head
- tail
- sed
- awk
- xargs
- find
- cat
- pwd

## Tool Usage

Never call:
- run_command
- todo
- dir

Only use tools that actually exist.

If a tool is unavailable, continue with shell commands.

## Development Workflow

1. Inspect the repository.
2. Locate the relevant files.
3. Edit only the required files.
4. Preserve project architecture.
5. Never ask unnecessary questions.
6. Never stop to create a plan.
7. Finish the implementation before explaining it.

## Installer Rules

When modifying the installer:

- Detect Python.
- Download the latest Python from python.org if missing.
- Install silently.
- Verify PATH.
- Continue installation automatically.
- Show progress for every installation step.
- Never bundle Python inside the installer.

## Code Style

- Production-ready.
- No placeholder code.
- No TODO comments.
- No duplicate code.
- Explain completed changes after implementation.