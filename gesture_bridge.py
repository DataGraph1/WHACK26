"""
Webcam -> Godot bridge.
Sends your LEFT hand's gesture and your RIGHT index fingertip (the cursor)
to Godot over UDP, 127.0.0.1:4242, once per frame.

Setup:   pip install -r requirements-camera.txt
Run:     python gesture_bridge.py      (press q in the preview window to quit)
Godot starts this script with --no-preview and displays the camera in-game.
"""
import argparse
import base64
import json
import os
import socket
import sys
import time
import urllib.request

import cv2
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision
from hand_roles import extract_hand_packet

HOST, PORT = "127.0.0.1", 4242
PREVIEW_SIZE = (240, 135)
PREVIEW_EVERY = 3
MAX_PACKET_BYTES = 8000  # macOS limits local UDP datagrams to 9216 bytes by default.
MODEL = "gesture_recognizer.task"
MODEL_URL = ("https://storage.googleapis.com/mediapipe-models/gesture_recognizer/"
             "gesture_recognizer/float16/1/gesture_recognizer.task")

parser = argparse.ArgumentParser()
parser.add_argument("--no-preview", action="store_true", help="Show video in Godot only")
parser.add_argument("--camera-index", type=int, help="Use a specific webcam index")
parser.add_argument("--swap-hands", action="store_true", help="Reverse hand roles for a camera that supplies mirrored frames")
args = parser.parse_args()
swap_hands = args.swap_hands or os.getenv("WHACK_SWAP_HANDS") == "1"

if not os.path.exists(MODEL):
    print("Downloading gesture model...")
    urllib.request.urlretrieve(MODEL_URL, MODEL)

recognizer = vision.GestureRecognizer.create_from_options(
    vision.GestureRecognizerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=MODEL),
        running_mode=vision.RunningMode.VIDEO,
        num_hands=2,
    )
)

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)


def open_working_camera():
    backend = cv2.CAP_AVFOUNDATION if sys.platform == "darwin" else cv2.CAP_ANY
    candidates = [args.camera_index] if args.camera_index is not None else [0, 1, 2]
    for attempt in range(8 if sys.platform == "darwin" else 1):
        for index in candidates:
            capture = cv2.VideoCapture(index, backend)
            if not capture.isOpened():
                capture.release()
                continue
            for _ in range(10):
                ok, test_frame = capture.read()
                if ok and test_frame.std() >= 1.0:
                    return capture, index
                time.sleep(0.1)
            capture.release()
            print(f"Camera {index} returned only black frames; trying another camera.", flush=True)
        if sys.platform == "darwin" and attempt == 0:
            notice = "Waiting for macOS Camera permission. Approve the popup; the game will retry for about 20 seconds."
            sock.sendto(json.dumps({"camera_notice": notice}).encode(), (HOST, PORT))
        if sys.platform == "darwin" and attempt < 7:
            time.sleep(2)
    raise RuntimeError("No working camera found. Check camera permission, privacy shutter, or use --camera-index.")


try:
    cap, camera_index = open_working_camera()
except RuntimeError as exc:
    message = ("Camera unavailable. In macOS System Settings > Privacy & Security > Camera, "
               "allow the listed Terminal, Python or Godot app, then quit and relaunch the game."
               if sys.platform == "darwin" else str(exc))
    sock.sendto(json.dumps({"camera_error": message}).encode(), (HOST, PORT))
    recognizer.close()
    sock.close()
    raise SystemExit(message) from exc
print(f"Using camera {camera_index}. Sending video and hand gestures to Godot on 127.0.0.1:4242.", flush=True)
start = time.monotonic()
cx, cy = 0.5, 0.5
failed_reads = 0
frame_number = 0

try:
    while cap.isOpened():
        ok, frame = cap.read()
        if not ok:
            failed_reads += 1
            if failed_reads >= 30:
                raise RuntimeError("Camera opened but did not return frames for 3 seconds.")
            time.sleep(0.1)
            continue
        failed_reads = 0
        # MediaPipe assigns anatomical Left/Right on the raw frame. Mirror only
        # the preview; flipping before inference reverses the task's labels.
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        result = recognizer.recognize_for_video(image, int((time.monotonic() - start) * 1000))
        frame_number += 1

        packet = extract_hand_packet(result, (cx, cy), swap_hands=swap_hands)
        cx, cy = packet["x"], packet["y"]
        packet["camera_index"] = camera_index
        if frame_number % PREVIEW_EVERY == 0:
            small_frame = cv2.resize(cv2.flip(frame, 1), PREVIEW_SIZE, interpolation=cv2.INTER_AREA)
            encoded_ok, jpeg = cv2.imencode(".jpg", small_frame, [cv2.IMWRITE_JPEG_QUALITY, 40])
            if encoded_ok:
                packet["frame_jpeg"] = base64.b64encode(jpeg).decode("ascii")
        payload = json.dumps(packet).encode()
        if len(payload) > MAX_PACKET_BYTES:
            packet.pop("frame_jpeg", None)
            payload = json.dumps(packet).encode()
        sock.sendto(payload, (HOST, PORT))

        if not args.no_preview:
            preview = cv2.flip(frame, 1)
            cv2.putText(preview, f"left: {packet['gesture']}  right: {packet['has_cursor']}", (10, 30),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 0), 2)
            cv2.imshow("gesture bridge (q to quit)", preview)
            if cv2.waitKey(1) & 0xFF == ord("q"):
                break
finally:
    cap.release()
    cv2.destroyAllWindows()
    recognizer.close()
    sock.close()
