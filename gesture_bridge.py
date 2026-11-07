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

HOST, PORT = "127.0.0.1", 4242
PREVIEW_SIZE = (240, 135)
PREVIEW_EVERY = 3
MAX_PACKET_BYTES = 8000  # macOS limits local UDP datagrams to 9216 bytes by default.
MODEL = "gesture_recognizer.task"
MODEL_URL = ("https://storage.googleapis.com/mediapipe-models/gesture_recognizer/"
             "gesture_recognizer/float16/1/gesture_recognizer.task")

MARGIN = 0.10       # ignore the outer 10% of the camera so the cursor can reach the screen edges
SMOOTH = 0.35       # 0 = frozen, 1 = no smoothing
SWAP_HANDS = False  # set True if Left/Right come out reversed on your setup

parser = argparse.ArgumentParser()
parser.add_argument("--no-preview", action="store_true", help="Show video in Godot only")
parser.add_argument("--camera-index", type=int, help="Use a specific webcam index")
args = parser.parse_args()

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
    raise RuntimeError("No working camera found. Check camera permission, privacy shutter, or use --camera-index.")


cap, camera_index = open_working_camera()
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
        # Mirror the frame (selfie view). MediaPipe's Left/Right labels then match your real hands.
        frame = cv2.flip(frame, 1)
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        result = recognizer.recognize_for_video(image, int((time.monotonic() - start) * 1000))
        frame_number += 1

        gesture, has_cursor = "None", False
        confidence = 0.0
        pointer_confidence = 0.0
        for i, hand in enumerate(result.handedness):
            if not hand:
                continue
            side = hand[0].category_name
            if SWAP_HANDS:
                side = "Right" if side == "Left" else "Left"
            if side == "Left" and i < len(result.gestures) and result.gestures[i]:
                gesture = result.gestures[i][0].category_name
                confidence = result.gestures[i][0].score
            elif side == "Right" and i < len(result.hand_landmarks) and len(result.hand_landmarks[i]) > 8:
                pointer_confidence = hand[0].score
                tip = result.hand_landmarks[i][8]            # index fingertip
                tx = min(max((tip.x - MARGIN) / (1 - 2 * MARGIN), 0.0), 1.0)
                ty = min(max((tip.y - MARGIN) / (1 - 2 * MARGIN), 0.0), 1.0)
                cx += (tx - cx) * SMOOTH
                cy += (ty - cy) * SMOOTH
                has_cursor = True

        packet = {"x": cx, "y": cy, "has_cursor": has_cursor,
                  "gesture": gesture, "confidence": confidence,
                  "pointer_confidence": pointer_confidence,
                  "hands": len(result.handedness), "camera_index": camera_index}
        if frame_number % PREVIEW_EVERY == 0:
            small_frame = cv2.resize(frame, PREVIEW_SIZE, interpolation=cv2.INTER_AREA)
            encoded_ok, jpeg = cv2.imencode(".jpg", small_frame, [cv2.IMWRITE_JPEG_QUALITY, 40])
            if encoded_ok:
                packet["frame_jpeg"] = base64.b64encode(jpeg).decode("ascii")
        payload = json.dumps(packet).encode()
        if len(payload) > MAX_PACKET_BYTES:
            packet.pop("frame_jpeg", None)
            payload = json.dumps(packet).encode()
        sock.sendto(payload, (HOST, PORT))

        if not args.no_preview:
            cv2.putText(frame, f"left: {gesture}  cursor: {has_cursor}", (10, 30),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 0), 2)
            cv2.imshow("gesture bridge (q to quit)", frame)
            if cv2.waitKey(1) & 0xFF == ord("q"):
                break
finally:
    cap.release()
    cv2.destroyAllWindows()
    recognizer.close()
    sock.close()
