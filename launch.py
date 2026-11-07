"""Start the checked local demo stack. Python 3.12+. Ctrl-C closes processes started here."""
from pathlib import Path
import argparse
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.request

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "narrator"))
from agent_api import ELEVENLABS_API_KEY, OLLAMA_MODEL


def read_json(url, timeout=2):
    with urllib.request.urlopen(url, timeout=timeout) as response:
        return json.load(response)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="Check setup without launching")
    args = parser.parse_args()
    godot = os.getenv("GODOT_BIN") or shutil.which("godot")
    if not godot and Path("/Applications/Godot.app/Contents/MacOS/Godot").exists():
        godot = "/Applications/Godot.app/Contents/MacOS/Godot"
    python = ROOT / (".venv/Scripts/python.exe" if os.name == "nt" else ".venv/bin/python")
    print("Godot:", "ready" if godot else "missing; set GODOT_BIN")
    print("Camera environment:", "present" if python.exists() else "missing; see README")
    print("ElevenLabs key:", "configured" if ELEVENLABS_API_KEY else "missing; captions only")
    owned = []
    logs = []
    runtime = ROOT / ".runtime"
    runtime.mkdir(exist_ok=True)
    def start(command, name, env=None):
        log = (runtime / (name + ".log")).open("w")
        logs.append(log)
        process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
        owned.append(process)
        return process
    try:
        try:
            models = read_json("http://127.0.0.1:11434/api/tags")
        except Exception:
            if args.check:
                print("Ollama: not running")
                return 1
            ollama = shutil.which("ollama")
            if not ollama:
                print("Install Ollama and pull", OLLAMA_MODEL)
                return 1
            env = os.environ.copy()
            local_models = ROOT.parent / "ollama-models"
            if local_models.exists():
                env["OLLAMA_MODELS"] = str(local_models)
            start([ollama, "serve"], "ollama", env)
            for _ in range(30):
                try:
                    models = read_json("http://127.0.0.1:11434/api/tags")
                    break
                except Exception:
                    time.sleep(0.2)
            else:
                print("Ollama failed to start; inspect .runtime/ollama.log")
                return 1
        names = {item["name"] for item in models.get("models", [])}
        if OLLAMA_MODEL not in names:
            print("Model missing. Run: ollama pull", OLLAMA_MODEL)
            return 1
        print("Text model:", OLLAMA_MODEL)
        try:
            narrator_health = read_json("http://127.0.0.1:8765/health")
        except Exception:
            narrator_health = None
        if narrator_health and narrator_health.get("text_model") != OLLAMA_MODEL:
            print("Narrator is still running with", narrator_health.get("text_model"),
                  "; restart that service before launching this version")
            return 1
        if args.check:
            return 0 if godot and python.exists() else 1
        request = urllib.request.Request("http://127.0.0.1:11434/api/generate", data=json.dumps(
            {"model": OLLAMA_MODEL, "prompt": "", "keep_alive": "1h"}).encode(), headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(request, timeout=60) as response:
            response.read()
        if not narrator_health:
            start([sys.executable, "narrator/agent_api.py"], "narrator")
            for _ in range(30):
                try:
                    read_json("http://127.0.0.1:8765/health")
                    break
                except Exception:
                    time.sleep(0.2)
            else:
                print("Narrator failed to start; inspect .runtime/narrator.log")
                return 1
        if not godot:
            return 1
        print("Opening game. Logs: .runtime/. Press Ctrl-C here to stop.")
        return start([godot, "--path", str(ROOT)], "game").wait()
    except KeyboardInterrupt:
        return 0
    finally:
        for process in reversed(owned):
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
        for log in logs:
            log.close()

if __name__ == "__main__":
    raise SystemExit(main())
