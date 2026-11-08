"""The automatic bridge must never fall through to an iPhone camera."""

import json
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from camera_devices import camera_candidates


class CameraDeviceTest(unittest.TestCase):
    def setUp(self):
        self.devices = json.dumps([
            {"index": 0, "name": "Kavya's iPhone Camera", "type": "AVCaptureDeviceTypeExternal"},
            {"index": 1, "name": "FaceTime HD Camera", "type": "AVCaptureDeviceTypeBuiltInWideAngleCamera"},
        ])

    def test_mac_selects_builtin_even_when_phone_is_first(self):
        with patch("camera_devices.subprocess.run", return_value=SimpleNamespace(stdout=self.devices)):
            self.assertEqual(camera_candidates(platform="darwin"), [1])
            with self.assertRaisesRegex(RuntimeError, "not the Mac's built-in camera"):
                camera_candidates(0, platform="darwin")

    def test_mac_does_not_fall_back_to_phone(self):
        only_phone = json.dumps([{"index": 0, "name": "iPhone", "type": "AVCaptureDeviceTypeExternal"}])
        with patch("camera_devices.subprocess.run", return_value=SimpleNamespace(stdout=only_phone)):
            with self.assertRaisesRegex(RuntimeError, "No built-in laptop camera"):
                camera_candidates(platform="darwin")

    def test_windows_uses_only_default_index(self):
        self.assertEqual(camera_candidates(platform="win32"), [0])


if __name__ == "__main__":
    unittest.main()
