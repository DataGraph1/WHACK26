"""
Webcam -> Godot bridge.
Sends your LEFT hand's gesture and your RIGHT index fingertip (the cursor)
to Godot over UDP, 127.0.0.1:4242, once per frame.

Setup:   pip install -r requirements-camera.txt
Run:     python gesture_bridge.py      (press q in the preview window to quit)
Godot starts this script with --no-preview and displays the camera in-game.
"""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
import socket
import sys
from threading import Lock, Thread
import time
import urllib.request

import cv2
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision
from hand_roles import extract_hand_packet
from camera_devices import camera_candidates

HOST, PORT = "127.0.0.1", 4242
PREVIEW_PORT = 4243
PREVIEW_EVERY = 2
PREVIEW_QUALITY = 85
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
preview_lock = Lock()
latest_preview_jpeg = b""


class PreviewHandler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_GET(self):
        if self.path != "/frame.jpg":
            self.send_error(404)
            return
        with preview_lock:
            frame = latest_preview_jpeg
        if not frame:
            self.send_error(503)
            return
        self.send_response(200)
        self.send_header("Content-Type", "image/jpeg")
        self.send_header("Content-Length", str(len(frame)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(frame)


try:
    preview_server = ThreadingHTTPServer((HOST, PREVIEW_PORT), PreviewHandler)
except OSError as exc:
    message = f"Camera preview port {PREVIEW_PORT} is unavailable; close any older game or bridge process: {exc}"
    sock.sendto(json.dumps({"camera_error": message}).encode(), (HOST, PORT))
    recognizer.close()
    sock.close()
    raise SystemExit(message) from exc
Thread(target=preview_server.serve_forever, daemon=True).start()


def open_working_camera():
    backend = cv2.CAP_AVFOUNDATION if sys.platform == "darwin" else cv2.CAP_ANY
    candidates = camera_candidates(args.camera_index)
    native_tried = False
    for attempt in range(8 if sys.platform == "darwin" else 1):
        for index in candidates:
            capture = cv2.VideoCapture(index, backend)
            opened = capture.isOpened()
            if opened:
                capture.set(cv2.CAP_PROP_FRAME_WIDTH, 1920)
                capture.set(cv2.CAP_PROP_FRAME_HEIGHT, 1080)
                for _ in range(10):
                    ok, test_frame = capture.read()
                    if ok and test_frame.std() >= 1.0:
                        return capture, index
                    time.sleep(0.1)
            capture.release()
            failure = "returned only black frames" if opened else "could not open through OpenCV"
            print(f"Camera {index} {failure}; trying native capture.", flush=True)
            if sys.platform == "darwin" and not native_tried:
                native_tried = True
                native_capture = None
                try:
                    from native_camera import BuiltinCameraCapture
                    native_capture = BuiltinCameraCapture(index)
                    for _ in range(4):
                        ok, test_frame = native_capture.read()
                        if ok and test_frame.std() >= 1.0:
                            print("Using native AVFoundation built-in camera after OpenCV failed.", flush=True)
                            return native_capture, index
                    raise RuntimeError(native_capture.error or "native capture returned no usable frame")
                except (ImportError, RuntimeError, OSError, ValueError) as exc:
                    print(f"Native built-in camera fallback unavailable: {exc}", flush=True)
                    if native_capture is not None:
                        native_capture.release()
        if sys.platform == "darwin" and attempt == 0:
            try:
                import AVFoundation as av
                authorized = int(av.AVCaptureDevice.authorizationStatusForMediaType_(av.AVMediaTypeVideo)) == 3
            except ImportError:
                authorized = False
            notice = ("Built-in camera capture failed; retrying."
                      if authorized else
                      "Waiting for macOS Camera permission. Approve the popup; the game will retry for about 20 seconds.")
            sock.sendto(json.dumps({"camera_notice": notice}).encode(), (HOST, PORT))
        if sys.platform == "darwin" and attempt < 7:
            time.sleep(2)
    raise RuntimeError("Laptop camera unavailable. Check camera access or close other camera apps.")


try:
    cap, camera_index = open_working_camera()
except RuntimeError as exc:
    message = str(exc)
    if sys.platform == "darwin":
        try:
            import AVFoundation as av
            status = int(av.AVCaptureDevice.authorizationStatusForMediaType_(av.AVMediaTypeVideo))
        except ImportError:
            status = -1
        if status in (0, 2):
            message += " In System Settings > Privacy & Security > Camera, allow Python, then relaunch."
        elif status == 1:
            message += " macOS has restricted camera access; check device restrictions."
        elif status == 3:
            message += " Python already has camera permission; check for another camera app or restart the laptop."
        else:
            message += " Install the camera packages from requirements-camera.txt, then relaunch."
    sock.sendto(json.dumps({"camera_error": message}).encode(), (HOST, PORT))
    recognizer.close()
    sock.close()
    raise SystemExit(message) from exc
print(f"Using camera {camera_index}. Sending video and hand gestures to Godot on 127.0.0.1:4242.", flush=True)
print(f"Camera capture: {int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))}x{int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))}; full-size preview on 127.0.0.1:{PREVIEW_PORT}.", flush=True)
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
        tracking_frame = frame
        if frame.shape[1] > 960:
            tracking_frame = cv2.resize(frame, (960, round(frame.shape[0] * 960 / frame.shape[1])), interpolation=cv2.INTER_AREA)
        rgb = cv2.cvtColor(tracking_frame, cv2.COLOR_BGR2RGB)
        image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        result = recognizer.recognize_for_video(image, int((time.monotonic() - start) * 1000))
        frame_number += 1

        packet = extract_hand_packet(result, (cx, cy), swap_hands=swap_hands)
        cx, cy = packet["x"], packet["y"]
        packet["camera_index"] = camera_index
        if frame_number % PREVIEW_EVERY == 0:
            encoded_ok, jpeg = cv2.imencode(".jpg", cv2.flip(frame, 1),
                                            [cv2.IMWRITE_JPEG_QUALITY, PREVIEW_QUALITY])
            if encoded_ok:
                with preview_lock:
                    latest_preview_jpeg = jpeg.tobytes()
        payload = json.dumps(packet).encode()
        if len(payload) > MAX_PACKET_BYTES:
            raise RuntimeError("Gesture packet unexpectedly exceeded local UDP limit")
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
    preview_server.shutdown()
    cv2.destroyAllWindows()
    recognizer.close()
    sock.close()
