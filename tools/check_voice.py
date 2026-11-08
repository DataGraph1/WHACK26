"""Make one short Liam voice request and save an MP3 without revealing the API key."""

import base64
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "narrator"))
from agent_api import ELEVENLABS_API_KEY, ELEVENLABS_VOICE_NAME, NarratorAgent, NarratorUnavailable


def main():
    if not ELEVENLABS_API_KEY:
        print("Missing ELEVENLABS_API_KEY. Copy narrator/.env.example to narrator/.env and add a team key.")
        return 1
    try:
        encoded = NarratorAgent()._speech("Robot online. Let's get this bomb defused!", "cheerful")
    except NarratorUnavailable as exc:
        print("Liam voice check failed:", exc)
        return 1
    output = ROOT / ".runtime" / "liam-voice-check.mp3"
    output.parent.mkdir(exist_ok=True)
    output.write_bytes(base64.b64decode(encoded))
    print("Liam voice ready:", ELEVENLABS_VOICE_NAME)
    print("Audio saved to:", output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
