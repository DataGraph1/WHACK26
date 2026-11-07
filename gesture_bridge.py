"""
Webcam -> Godot bridge.
Sends your LEFT hand's gesture and your RIGHT index fingertip (the cursor)
to Godot over UDP, 127.0.0.1:4242, once per frame.

Setup:   pip install mediapipe opencv-python
Run:     python gesture_bridge.py      (press q in the preview window to quit)
"""
import json
import os
import socket
import time
import urllib.request

import cv2
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision

HOST, PORT = "127.0.0.1", 4242
MODEL = "gesture_recognizer.task"
MODEL_URL = ("https://storage.googleapis.com/mediapipe-models/gesture_recognizer/"
             "gesture_recognizer/float16/1/gesture_recognizer.task")

MARGIN = 0.10       # ignore the outer 10% of the camera so the cursor can reach the screen edges
SMOOTH = 0.35       # 0 = frozen, 1 = no smoothing
SWAP_HANDS = False  # set True if Left/Right come out reversed on your setup

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
cap = cv2.VideoCapture(0)
start = time.time()
cx, cy = 0.5, 0.5

while cap.isOpened():
    ok, frame = cap.read()
    if not ok:
        break
    # Mirror the frame (selfie view). MediaPipe's Left/Right labels then match your real hands.
    frame = cv2.flip(frame, 1)
    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
    result = recognizer.recognize_for_video(image, int((time.time() - start) * 1000))

    gesture, has_cursor = "None", False
    for i, hand in enumerate(result.handedness):
        side = hand[0].category_name
        if SWAP_HANDS:
            side = "Right" if side == "Left" else "Left"
        if side == "Left" and result.gestures:
            gesture = result.gestures[i][0].category_name
        elif side == "Right":
            tip = result.hand_landmarks[i][8]            # index fingertip
            tx = min(max((tip.x - MARGIN) / (1 - 2 * MARGIN), 0.0), 1.0)
            ty = min(max((tip.y - MARGIN) / (1 - 2 * MARGIN), 0.0), 1.0)
            cx += (tx - cx) * SMOOTH
            cy += (ty - cy) * SMOOTH
            has_cursor = True

    packet = {"x": cx, "y": cy, "has_cursor": has_cursor, "gesture": gesture}
    sock.sendto(json.dumps(packet).encode(), (HOST, PORT))

    cv2.putText(frame, f"left: {gesture}  cursor: {has_cursor}", (10, 30),
                cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 0), 2)
    cv2.imshow("gesture bridge (q to quit)", frame)
    if cv2.waitKey(1) & 0xFF == ord("q"):
        break

cap.release()
cv2.destroyAllWindows()
