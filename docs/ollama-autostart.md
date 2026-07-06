# Automatic Ollama Initialization

## Overview

HELIX now automatically manages the Ollama service on startup. When you launch the HELIX executable, it will:

1. **Check for Ollama** - Searches for Ollama installation on your system
2. **Install if needed** (Windows only) - Automatically downloads and installs Ollama from https://ollama.com if not found
3. **Start Ollama** - Launches the Ollama service if not already running
4. **Verify availability** - Checks that Ollama is responding on `http://127.0.0.1:11434`
5. **Ensure a model** - Pulls a default model (`qwen2.5:4b`) if no models are installed
6. **Use fallbacks** - Falls back to alternative models (`llama2`, `neural-chat`) if the primary model fails

## What Happens on Startup

### First Time (Windows)
- HELIX detects Ollama is missing
- Downloads OllamaSetup.exe (~600MB)
- Runs the installer silently
- Starts the Ollama service
- Pulls the default model (~2.5GB for qwen2.5:4b)
- Launches HELIX interface
- **Total time: 5-10 minutes** depending on internet speed

### Subsequent Runs
- HELIX detects Ollama is already installed
- Starts the service (if not running)
- Verifies the model is available
- Launches instantly (~3 seconds)

## Platform Support

| Platform | Auto-Install | Auto-Start | Model Pull |
|----------|-------------|-----------|-----------|
| Windows | ✅ Yes | ✅ Yes | ✅ Yes |
| Linux | ❌ No* | ✅ Yes | ✅ Yes |
| macOS | ❌ No* | ✅ Yes | ✅ Yes |

*On Linux/macOS, Ollama must be pre-installed manually via `brew install ollama` or https://ollama.com

## Installation Requirements

### Windows
- **Disk space**: At least 12 GB free (for HELIX + Ollama + model)
- **Internet**: Required for first-time setup (~2-3GB download)
- **No manual installation needed** - HELIX handles it automatically

### Linux/macOS
```bash
# macOS (via Homebrew)
brew install ollama

# Linux
curl https://ollama.ai/install.sh | sh
```

## Configuration

No configuration is required. HELIX uses sensible defaults:

- **Ollama URL**: `http://127.0.0.1:11434`
- **Default model**: `qwen2.5:4b` (4B parameters, ~2.5GB)
- **Fallback models**: `llama2`, `neural-chat`

To use a different model after startup, you can:
1. Pull additional models via Ollama CLI: `ollama pull llama2`
2. Select the model in the HELIX UI under Model Settings

## Troubleshooting

### Ollama won't start
1. Check if port 11434 is in use: `netstat -an | findstr :11434` (Windows)
2. Verify Ollama is installed: `ollama --version`
3. Try starting manually: `ollama serve`

### Model pull fails
1. **Check internet connection**: Model downloads require 2-5 GB
2. **Free disk space**: Ensure at least 10 GB free space
3. **Pull manually**: `ollama pull qwen2.5:4b`

### Application still works without Ollama
- If Ollama initialization fails, HELIX still starts
- You can use other LLM providers (Claude, OpenAI, etc.)
- Ollama features simply won't be available

## Performance Notes

- **First startup**: 5-10 minutes (installation + model download)
- **Subsequent startups**: ~3 seconds
- **Memory usage**: Ollama uses 4-8 GB depending on model
- **Model inference**: ~100ms per token on typical hardware

## Advanced: Manual Ollama Setup

If you prefer to manage Ollama separately:

```bash
# Install manually
# (See https://ollama.com)

# Start Ollama in one terminal
ollama serve

# Pull models
ollama pull qwen2.5:4b
ollama pull llama2
ollama pull mistral

# In another terminal, start HELIX
python launcher.py
```

The automatic initialization will detect your running Ollama and skip installation/startup steps.

## See Also
- [Ollama Documentation](https://ollama.com)
- [Available Models](https://ollama.com/library)
- [HELIX Setup Guide](./setup.md)
