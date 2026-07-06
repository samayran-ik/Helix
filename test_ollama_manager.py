#!/usr/bin/env python3
"""Quick test script to verify Ollama manager functionality without starting the full app."""

import sys
import os

# Add project to path
sys.path.insert(0, os.path.dirname(__file__))

from core.ollama_manager import OllamaManager

def test_ollama_manager():
    """Test the Ollama manager without full initialization."""
    print("=" * 60)
    print("HELIX Ollama Manager - Quick Test")
    print("=" * 60)
    
    manager = OllamaManager()
    
    # Test 1: Find Ollama
    print("\n[Test 1] Searching for Ollama executable...")
    ollama_exe = manager.find_ollama_exe()
    if ollama_exe:
        print(f"✓ Found: {ollama_exe}")
    else:
        print("✗ Not found (will auto-install on Windows during normal startup)")
    
    # Test 2: Check if running
    print("\n[Test 2] Checking if Ollama is running...")
    if manager.is_ollama_running():
        print("✓ Ollama is running")
        
        # Test 3: Get available models
        print("\n[Test 3] Fetching available models...")
        models = manager.get_available_models()
        if models:
            print(f"✓ Found {len(models)} model(s):")
            for model in models:
                print(f"  - {model}")
        else:
            print("✗ No models installed yet")
    else:
        print("✗ Ollama is not running")
        print("\nNote: Ollama will be started automatically when you run HELIX.")
        print("      You can also start it manually: ollama serve")
    
    print("\n" + "=" * 60)
    print("Summary")
    print("=" * 60)
    print("""
When you run HELIX (launcher.py), it will:
  1. Check for Ollama installation
  2. Install Ollama if missing (Windows only)
  3. Start Ollama if not running
  4. Verify Ollama is responding
  5. Ensure a model is available
  
Full initialization will begin automatically on next startup.
    """)

if __name__ == "__main__":
    test_ollama_manager()
