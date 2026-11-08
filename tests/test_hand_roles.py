"""Camera hand roles are independent of MediaPipe's result ordering."""
from types import SimpleNamespace as Item
import unittest

from hand_roles import extract_hand_packet


def category(name, score=0.9):
    return Item(category_name=name, score=score)


def landmarks(x=0.2, y=0.4):
    points = [Item(x=0.0, y=0.0) for _ in range(21)]
    points[8] = Item(x=x, y=y)
    return points


class HandRoleTest(unittest.TestCase):
    def test_left_commands_and_right_points_in_either_result_order(self):
        for reverse in (False, True):
            hands = [([category("Left")], [category("Victory", 0.82)], landmarks(0.8)),
                     ([category("Right")], [category("Pointing_Up", 0.95)], landmarks(0.2))]
            if reverse:
                hands.reverse()
            result = Item(handedness=[hand[0] for hand in hands],
                          gestures=[hand[1] for hand in hands],
                          hand_landmarks=[hand[2] for hand in hands])
            packet = extract_hand_packet(result)
            self.assertEqual(packet["hands"], 2)
            self.assertTrue(packet["left_detected"] and packet["right_detected"])
            self.assertEqual(packet["gesture"], "Victory")
            self.assertEqual(packet["confidence"], 0.82)
            self.assertTrue(packet["has_cursor"])
            self.assertGreater(packet["x"], 0.5)  # right hand raw x=.2, mirrored preview x=.8

    def test_missing_command_hand_never_borrows_pointer_gesture(self):
        result = Item(handedness=[[category("Right")]],
                      gestures=[[category("Victory")]],
                      hand_landmarks=[landmarks()])
        packet = extract_hand_packet(result)
        self.assertFalse(packet["left_detected"])
        self.assertEqual(packet["gesture"], "None")
        self.assertTrue(packet["right_detected"])

    def test_detected_left_hand_can_have_no_recognized_gesture(self):
        result = Item(handedness=[[category("Left")]],
                      gestures=[[]], hand_landmarks=[landmarks()])
        packet = extract_hand_packet(result)
        self.assertTrue(packet["left_detected"])
        self.assertEqual(packet["gesture"], "None")
        self.assertFalse(packet["right_detected"])

    def test_explicit_swap_supports_camera_with_mirrored_input(self):
        result = Item(handedness=[[category("Right")], [category("Left")]],
                      gestures=[[category("Open_Palm")], [category("None")]],
                      hand_landmarks=[landmarks(), landmarks()])
        packet = extract_hand_packet(result, swap_hands=True)
        self.assertEqual(packet["gesture"], "Open_Palm")
        self.assertTrue(packet["has_cursor"])

    def test_middle_camera_range_reaches_board_edges_with_less_arm_travel(self):
        for raw_x, start_x, upper_bound in ((0.78, 1.0, 0.60), (0.22, 0.0, 0.60)):
            result = Item(handedness=[[category("Right")]], gestures=[[]],
                          hand_landmarks=[landmarks(raw_x, 0.5)])
            x = extract_hand_packet(result, cursor=(start_x, 0.5))["x"]
            self.assertLess(x if raw_x > 0.5 else 1.0 - x, upper_bound)


if __name__ == "__main__":
    unittest.main()
