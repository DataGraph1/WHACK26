"""Choose only an integrated laptop camera for the hand-tracking bridge."""

import json
import subprocess
import sys


MAC_CAMERA_LIST = r'''
ObjC.import("AVFoundation");
var devices = $.NSClassFromString("AVCaptureDevice").devicesWithMediaType($.AVMediaTypeVideo);
var cameras = [];
for (var i = 0; i < devices.count; i++) {
    var device = devices.objectAtIndex(i);
    cameras.push({index: i, name: ObjC.unwrap(device.localizedName),
                  type: ObjC.unwrap(device.deviceType)});
}
JSON.stringify(cameras);
'''


def camera_candidates(requested_index=None, platform=None):
    """Return AVFoundation indices for built-in cameras; never select Continuity/USB."""
    platform = sys.platform if platform is None else platform
    if platform != "darwin":
        return [0 if requested_index is None else requested_index]
    try:
        result = subprocess.run(
            ["osascript", "-l", "JavaScript", "-e", MAC_CAMERA_LIST],
            check=True, capture_output=True, text=True, timeout=5)
        cameras = json.loads(result.stdout)
    except (OSError, subprocess.SubprocessError, ValueError) as exc:
        raise RuntimeError("Could not identify the Mac's built-in camera; refusing other cameras") from exc
    built_in = [camera["index"] for camera in cameras
                if str(camera.get("type", "")).startswith("AVCaptureDeviceTypeBuiltIn")]
    if requested_index is not None:
        if requested_index not in built_in:
            raise RuntimeError("Camera index %d is not the Mac's built-in camera" % requested_index)
        return [requested_index]
    if not built_in:
        raise RuntimeError("No built-in laptop camera found; phone and external cameras are disabled")
    return built_in
