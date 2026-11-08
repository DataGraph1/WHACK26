"""Open the Mac's integrated camera through AVFoundation when OpenCV returns black."""

import ctypes
import threading

import AVFoundation as av
import CoreMedia
from Foundation import NSObject
import numpy as np
import objc
import Quartz


class _FrameReceiver(NSObject):
    def initWithOwner_(self, owner):
        self = objc.super(_FrameReceiver, self).init()
        if self is not None:
            self.owner = owner
        return self

    def captureOutput_didOutputSampleBuffer_fromConnection_(self, _output, sample, _connection):
        pixel = CoreMedia.CMSampleBufferGetImageBuffer(sample)
        if pixel is None or Quartz.CVPixelBufferLockBaseAddress(pixel, 0) != 0:
            return
        try:
            height = Quartz.CVPixelBufferGetHeight(pixel)
            width = Quartz.CVPixelBufferGetWidth(pixel)
            row_bytes = Quartz.CVPixelBufferGetBytesPerRow(pixel)
            base = Quartz.CVPixelBufferGetBaseAddress(pixel)
            if base is objc.NULL:
                return
            # The output is BGRA; OpenCV/MediaPipe and the JPEG preview use BGR.
            pixels = np.frombuffer(base.as_buffer(row_bytes * height), dtype=np.uint8)
            frame = pixels.reshape(height, row_bytes // 4, 4)[:, :width, :3].copy()
            self.owner._receive(frame)
        except Exception as exc:
            self.owner.error = f"AVFoundation frame conversion failed: {exc}"
        finally:
            Quartz.CVPixelBufferUnlockBaseAddress(pixel, 0)


class BuiltinCameraCapture:
    """Minimal VideoCapture-compatible reader, restricted to built-in AVFoundation devices."""

    def __init__(self, index=0):
        devices = list(av.AVCaptureDevice.devicesWithMediaType_(av.AVMediaTypeVideo))
        if index >= len(devices) or not str(devices[index].deviceType()).startswith(
                "AVCaptureDeviceTypeBuiltIn"):
            raise RuntimeError("Selected camera is not the Mac's built-in camera")
        self._condition = threading.Condition()
        self._latest = None
        self._sequence = 0
        self._consumed = 0
        self.error = ""

        device_input, error = av.AVCaptureDeviceInput.deviceInputWithDevice_error_(devices[index], None)
        if device_input is None:
            raise RuntimeError(f"AVFoundation could not open built-in camera: {error}")
        self._session = av.AVCaptureSession.alloc().init()
        self._session.setSessionPreset_(av.AVCaptureSessionPresetHigh)
        self._session.addInput_(device_input)
        self._output = av.AVCaptureVideoDataOutput.alloc().init()
        self._output.setVideoSettings_({Quartz.kCVPixelBufferPixelFormatTypeKey:
                                        Quartz.kCVPixelFormatType_32BGRA})
        self._output.setAlwaysDiscardsLateVideoFrames_(True)

        dispatch = ctypes.CDLL("/usr/lib/system/libdispatch.dylib")
        dispatch.dispatch_queue_create.argtypes = [ctypes.c_char_p, ctypes.c_void_p]
        dispatch.dispatch_queue_create.restype = ctypes.c_void_p
        pointer = dispatch.dispatch_queue_create(b"whack.builtin.camera", None)
        if not pointer:
            raise RuntimeError("AVFoundation could not create its capture queue")
        self._queue = objc.objc_object(c_void_p=pointer)
        self._receiver = _FrameReceiver.alloc().initWithOwner_(self)
        self._output.setSampleBufferDelegate_queue_(self._receiver, self._queue)
        self._session.addOutput_(self._output)
        self._session.startRunning()

    def _receive(self, frame):
        with self._condition:
            self._latest = frame
            self._sequence += 1
            self._condition.notify_all()

    def isOpened(self):
        return bool(self._session.isRunning())

    def read(self):
        with self._condition:
            self._condition.wait_for(lambda: self._sequence != self._consumed or self.error,
                                     timeout=2.0)
            if self._sequence == self._consumed:
                return False, None
            self._consumed = self._sequence
            return True, self._latest

    def get(self, property_id):
        import cv2
        if self._latest is None:
            return 0.0
        if property_id == cv2.CAP_PROP_FRAME_WIDTH:
            return float(self._latest.shape[1])
        if property_id == cv2.CAP_PROP_FRAME_HEIGHT:
            return float(self._latest.shape[0])
        return 0.0

    def release(self):
        if self._session.isRunning():
            self._session.stopRunning()
        self._output.setSampleBufferDelegate_queue_(None, None)
