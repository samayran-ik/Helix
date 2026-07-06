"""Ollama service manager for automatic startup, installation, and model management."""
import os
import sys
import subprocess
import time
import requests
import logging
import json
import platform
from pathlib import Path
from typing import Optional, Tuple

logger = logging.getLogger(__name__)

OLLAMA_API_URL = "http://127.0.0.1:11434"
OLLAMA_HEALTH_CHECK_ENDPOINT = f"{OLLAMA_API_URL}/api/tags"
DEFAULT_MODEL = "qwen2.5:4b"
FALLBACK_MODELS = ["llama2", "neural-chat"]
OLLAMA_DOWNLOAD_URL = "https://ollama.com/download"


class OllamaManager:
    """Manages Ollama service lifecycle: detection, startup, installation, and model management."""
    
    def __init__(self):
        self.ollama_exe: Optional[str] = None
        self.is_service = False
        
    def find_ollama_exe(self) -> Optional[str]:
        """Find Ollama executable on the system.
        
        Returns:
            Path to ollama.exe (Windows) or ollama (Linux/macOS), or None if not found.
        """
        if self.ollama_exe:
            return self.ollama_exe
        
        # Check if ollama is in PATH
        try:
            result = subprocess.run(
                ["where", "ollama.exe"] if sys.platform == "win32" else ["which", "ollama"],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                path = result.stdout.strip()
                if path:
                    self.ollama_exe = path
                    return path
        except Exception as e:
            logger.debug(f"Failed to find ollama in PATH: {e}")
        
        # Common installation paths
        if sys.platform == "win32":
            candidates = [
                os.path.expandvars(r"%LOCALAPPDATA%\Programs\Ollama\ollama.exe"),
                os.path.expandvars(r"%LOCALAPPDATA%\Ollama\ollama.exe"),
                os.path.expandvars(r"%ProgramFiles%\Ollama\ollama.exe"),
                os.path.expandvars(r"%ProgramFiles(x86)%\Ollama\ollama.exe"),
            ]
        elif sys.platform == "darwin":  # macOS
            candidates = [
                "/usr/local/bin/ollama",
                "/opt/homebrew/bin/ollama",
            ]
        else:  # Linux
            candidates = [
                "/usr/local/bin/ollama",
                "/usr/bin/ollama",
            ]
        
        for candidate in candidates:
            if os.path.isfile(candidate):
                self.ollama_exe = candidate
                return candidate
        
        logger.warning("Ollama executable not found on system")
        return None
    
    def is_ollama_running(self) -> bool:
        """Check if Ollama service is running by making a health check request.
        
        Returns:
            True if Ollama responds to health check, False otherwise.
        """
        try:
            response = requests.get(OLLAMA_HEALTH_CHECK_ENDPOINT, timeout=3)
            return response.status_code < 500
        except (requests.ConnectionError, requests.Timeout, Exception):
            return False
    
    def wait_for_ollama(self, timeout_seconds: int = 120) -> bool:
        """Wait for Ollama to become ready.
        
        Args:
            timeout_seconds: Maximum time to wait in seconds.
            
        Returns:
            True if Ollama became ready, False if timeout.
        """
        deadline = time.time() + timeout_seconds
        while time.time() < deadline:
            if self.is_ollama_running():
                logger.info("✓ Ollama is ready")
                return True
            time.sleep(2)
        
        logger.error(f"✗ Ollama did not respond after {timeout_seconds} seconds")
        return False
    
    def check_service_running(self) -> bool:
        """Check if Ollama is running as a service or process.
        
        Returns:
            True if Ollama service or process is running.
        """
        if sys.platform == "win32":
            try:
                result = subprocess.run(
                    ["tasklist", "/FI", "IMAGENAME eq ollama.exe"],
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                return "ollama.exe" in result.stdout
            except Exception:
                return False
        else:
            try:
                result = subprocess.run(
                    ["pgrep", "-l", "ollama"],
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                return result.returncode == 0
            except Exception:
                return False
    
    def start_ollama(self) -> bool:
        """Start Ollama service or process.
        
        Returns:
            True if Ollama was started successfully or is already running.
        """
        # Check if already running
        if self.check_service_running() or self.is_ollama_running():
            logger.info("✓ Ollama is already running")
            return True
        
        ollama_exe = self.find_ollama_exe()
        if not ollama_exe:
            logger.error("✗ Ollama executable not found")
            return False
        
        logger.info(f"Starting Ollama from: {ollama_exe}")
        
        try:
            if sys.platform == "win32":
                # Try to start as service first
                try:
                    subprocess.run(
                        ["net", "start", "Ollama"],
                        capture_output=True,
                        timeout=10
                    )
                    self.is_service = True
                    logger.info("✓ Started Ollama service")
                except Exception:
                    # Fallback to running as process
                    subprocess.Popen(
                        [ollama_exe, "serve"],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        creationflags=subprocess.CREATE_NO_WINDOW
                    )
                    logger.info("✓ Started Ollama process")
            else:
                # Linux/macOS - start as process
                subprocess.Popen(
                    [ollama_exe, "serve"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    preexec_fn=os.setsid if hasattr(os, 'setsid') else None
                )
                logger.info("✓ Started Ollama process")
            
            # Wait for Ollama to be ready
            return self.wait_for_ollama()
        except Exception as e:
            logger.error(f"✗ Failed to start Ollama: {e}")
            return False
    
    def get_available_models(self) -> list:
        """Get list of available models from Ollama.
        
        Returns:
            List of model names, or empty list if unable to fetch.
        """
        try:
            response = requests.get(f"{OLLAMA_API_URL}/api/tags", timeout=5)
            if response.status_code == 200:
                data = response.json()
                models = data.get("models", [])
                return [m.get("name", "") for m in models if m.get("name")]
            return []
        except Exception as e:
            logger.debug(f"Failed to get available models: {e}")
            return []
    
    def has_model(self, model_name: str) -> bool:
        """Check if a specific model is available in Ollama.
        
        Args:
            model_name: Name of the model to check.
            
        Returns:
            True if model is available.
        """
        available_models = self.get_available_models()
        # Check for exact match or partial match (for versions)
        for model in available_models:
            if model.startswith(model_name.split(":")[0]):
                return True
        return False
    
    def pull_model(self, model_name: str, timeout_seconds: int = 600) -> bool:
        """Pull a model from Ollama repository.
        
        Args:
            model_name: Name of the model to pull (e.g., "qwen2.5:4b").
            timeout_seconds: Maximum time to wait in seconds.
            
        Returns:
            True if model was pulled successfully.
        """
        ollama_exe = self.find_ollama_exe()
        if not ollama_exe:
            logger.error("✗ Ollama executable not found")
            return False
        
        logger.info(f"Pulling model: {model_name}")
        
        try:
            process = subprocess.Popen(
                [ollama_exe, "pull", model_name],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
            )
            
            stdout, stderr = process.communicate(timeout=timeout_seconds)
            
            if process.returncode == 0:
                logger.info(f"✓ Model {model_name} pulled successfully")
                return True
            else:
                logger.error(f"✗ Failed to pull model {model_name}")
                if stderr:
                    logger.error(f"  Error: {stderr}")
                return False
        except subprocess.TimeoutExpired:
            process.kill()
            logger.error(f"✗ Model pull timed out after {timeout_seconds} seconds")
            return False
        except Exception as e:
            logger.error(f"✗ Failed to pull model: {e}")
            return False
    
    def install_ollama(self) -> bool:
        """Install Ollama on Windows (if not already installed).
        
        Returns:
            True if installation was successful or Ollama already exists.
        """
        if sys.platform != "win32":
            logger.info("Ollama installation via manager is Windows-only")
            return False
        
        # Check if already installed
        if self.find_ollama_exe():
            logger.info("✓ Ollama is already installed")
            return True
        
        logger.info("Installing Ollama...")
        
        try:
            # Download Ollama installer
            import urllib.request
            import tempfile
            
            installer_path = os.path.join(tempfile.gettempdir(), "OllamaSetup.exe")
            
            logger.info("Downloading Ollama installer...")
            download_url = f"{OLLAMA_DOWNLOAD_URL}/OllamaSetup.exe"
            urllib.request.urlretrieve(download_url, installer_path)
            
            if not os.path.exists(installer_path):
                logger.error("✗ Failed to download Ollama installer")
                return False
            
            logger.info("Running Ollama installer...")
            process = subprocess.Popen(
                [installer_path, "/S"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )
            process.wait(timeout=300)  # 5 minute timeout
            
            if process.returncode != 0:
                logger.error(f"✗ Ollama installer failed with exit code {process.returncode}")
                return False
            
            # Wait for Ollama to be available
            time.sleep(3)
            
            # Verify installation
            if self.find_ollama_exe():
                logger.info("✓ Ollama installed successfully")
                return True
            else:
                logger.error("✗ Ollama installer completed but executable not found")
                return False
        
        except Exception as e:
            logger.error(f"✗ Failed to install Ollama: {e}")
            return False
    
    def ensure_ollama_ready(self, auto_install: bool = True, model_name: Optional[str] = None) -> bool:
        """Ensure Ollama is running with a model ready.
        
        This is the main entry point that handles the full workflow:
        1. Find or install Ollama
        2. Start Ollama service
        3. Wait for it to be ready
        4. Pull a model if needed
        
        Args:
            auto_install: Whether to automatically install Ollama on Windows if not found.
            model_name: Model to ensure is available (defaults to DEFAULT_MODEL).
            
        Returns:
            True if Ollama is ready with a model, False otherwise.
        """
        if model_name is None:
            model_name = DEFAULT_MODEL
        
        logger.info("=" * 50)
        logger.info("Checking Ollama setup...")
        logger.info("=" * 50)
        
        # Step 1: Find or install Ollama
        if not self.find_ollama_exe():
            if auto_install and sys.platform == "win32":
                logger.info("Ollama not found, attempting installation...")
                if not self.install_ollama():
                    logger.error("✗ Failed to install Ollama")
                    return False
            else:
                logger.error("✗ Ollama not found and auto-install is disabled or not on Windows")
                logger.info("Please install Ollama manually from https://ollama.com")
                return False
        
        # Step 2: Start Ollama
        if not self.start_ollama():
            logger.error("✗ Failed to start Ollama")
            return False
        
        # Step 3: Check and pull model
        if not self.has_model(model_name):
            logger.info(f"Model {model_name} not found, pulling...")
            
            # Try to pull the default model
            if not self.pull_model(model_name):
                # Fallback to alternative models
                logger.info("Attempting fallback models...")
                for fallback_model in FALLBACK_MODELS:
                    if self.pull_model(fallback_model):
                        logger.info(f"✓ Successfully pulled fallback model: {fallback_model}")
                        return True
                
                logger.error("✗ Failed to pull any model")
                return False
        else:
            logger.info(f"✓ Model {model_name} is available")
        
        logger.info("=" * 50)
        logger.info("✓ Ollama is ready!")
        logger.info("=" * 50)
        return True
