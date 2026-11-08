"""Assign MediaPipe's unmirrored hand results to game controls."""

MARGIN = 0.10
SMOOTH = 0.35


def extract_hand_packet(result, cursor=(0.5, 0.5), swap_hands=False):
    """Right index moves the selfie-view cursor; left gesture gives commands."""
    cx, cy = cursor
    packet = {"x": cx, "y": cy, "has_cursor": False,
              "gesture": "None", "confidence": 0.0,
              "pointer_confidence": 0.0, "hands": len(result.handedness),
              "left_detected": False, "right_detected": False}
    best_left = -1.0
    best_right = -1.0
    for i, categories in enumerate(result.handedness):
        if not categories:
            continue
        category = categories[0]
        side = category.category_name
        if swap_hands:
            side = {"Left": "Right", "Right": "Left"}.get(side, side)
        if side == "Left":
            packet["left_detected"] = True
            if category.score > best_left:
                best_left = category.score
                gestures = result.gestures[i] if i < len(result.gestures) else []
                packet["gesture"] = gestures[0].category_name if gestures else "None"
                packet["confidence"] = gestures[0].score if gestures else 0.0
        elif side == "Right":
            landmarks = result.hand_landmarks[i] if i < len(result.hand_landmarks) else []
            if len(landmarks) <= 8:
                continue
            packet["right_detected"] = True
            if category.score > best_right:
                best_right = category.score
                tip = landmarks[8]
                # Recognition uses the raw frame. Mirror X for the selfie preview.
                tx = min(max(((1.0 - tip.x) - MARGIN) / (1 - 2 * MARGIN), 0.0), 1.0)
                ty = min(max((tip.y - MARGIN) / (1 - 2 * MARGIN), 0.0), 1.0)
                cx += (tx - cx) * SMOOTH
                cy += (ty - cy) * SMOOTH
                packet.update(x=cx, y=cy, has_cursor=True,
                              pointer_confidence=category.score)
    return packet
