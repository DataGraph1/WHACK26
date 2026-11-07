"""Stateful event decisions without calling Ollama or ElevenLabs."""

import unittest

from agent_api import NarratorAgent, NarratorUnavailable, validate_event


class FakeClock:
    def __init__(self):
        self.now = 100.0

    def __call__(self):
        return self.now


class FakeAgent(NarratorAgent):
    def __init__(self, clock):
        super().__init__(clock=clock)
        self.llm_calls = 0

    def _ask_llm(self, event, session, wrong_streak):
        self.llm_calls += 1
        return {"say": True, "text": f"Observed {event['kind']}",
                "mood": "cheerful", "reason": "Current observation merits a short line"}

    def _speech(self, text, mood):
        return "ZmFrZS1tcDM="


class NarratorStateTest(unittest.TestCase):
    def setUp(self):
        self.clock = FakeClock()
        self.agent = FakeAgent(clock=self.clock)
        self.next_id = 0

    def send(self, kind, context=None, result=None, game="wires", action=""):
        self.next_id += 1
        raw = {"session_id": "round-1", "event_id": str(self.next_id),
               "game": game, "kind": kind, "context": context or {},
               "action": action}
        if result is not None:
            raw["result"] = result
        return self.agent.handle(validate_event(raw))

    def test_pacing_and_time_warning_are_event_driven_and_not_repeated(self):
        self.send("round_started", {"lives": 3})
        self.clock.now = 112
        prompt = self.send("state", {"idle_seconds": 12, "right_hand_visible": True,
                                     "seconds_left": 90})
        self.assertEqual(prompt["trigger"], "hesitation")
        self.assertTrue(prompt["say"])
        self.clock.now = 115
        calls_before = self.agent.llm_calls
        self.assertFalse(self.send("state", {"idle_seconds": 15,
                                             "right_hand_visible": True})["say"])
        self.assertEqual(self.agent.llm_calls, calls_before)
        self.clock.now = 130
        warning = self.send("state", {"seconds_left": 29, "right_hand_visible": True})
        self.assertEqual(warning["trigger"], "time_warning")
        self.assertEqual(warning["mood"], "urgent")
        self.clock.now = 134
        self.assertFalse(self.send("state", {"seconds_left": 27})["say"])
        self.clock.now = 140
        self.assertEqual(self.send("state", {"seconds_left": 9})["trigger"], "time_warning")

    def test_uncertainty_has_cooldown_and_result_preserves_last_life(self):
        self.send("round_started", {"lives": 3})
        self.clock.now = 110
        uncertain = self.send("uncertainty", {"uncertainty_reason": "right_hand_missing"})
        self.assertEqual(uncertain["trigger"], "uncertainty")
        self.assertTrue(uncertain["say"])
        self.clock.now = 111
        self.assertFalse(self.send("uncertainty", {"uncertainty_reason": "right_hand_missing"})["say"])
        self.clock.now = 120
        result = self.send("result", {"lives": 1}, result="wrong", action="cut wire 2")
        self.assertEqual(result["mood"], "urgent")
        self.assertTrue(result["text"].startswith("Wrong choice."))
        self.clock.now = 124
        self.assertFalse(self.send("state", {"lives": 1})["say"])

    def test_round_memory_tracks_inspections_and_resets_on_new_round(self):
        self.send("round_started", {"lives": 3})
        self.clock.now = 105
        self.send("inspection_request", {"target": "wire 2"})
        self.send("result", {"lives": 2}, result="wrong")
        memory = self.agent.sessions["round-1"]
        self.assertEqual(memory.inspected_targets, [{"game": "wires", "target": "wire 2"}])
        self.assertEqual(memory.total_wrong, 1)
        self.clock.now = 110
        self.send("round_started", {"lives": 3})
        memory = self.agent.sessions["round-1"]
        self.assertEqual(memory.inspected_targets, [])
        self.assertEqual(memory.total_wrong, 0)


    def test_failed_speech_keeps_caption_and_memory(self):
        def unavailable(*args):
            raise NarratorUnavailable("test outage")
        self.agent._speech = unavailable
        result = self.send("result", {"lives": 2}, result="wrong")
        self.assertTrue(result["text"].startswith("Wrong choice."))
        self.assertEqual(result["audio_base64"], "")
        self.assertEqual(self.agent.sessions["round-1"].total_wrong, 1)

    def test_failed_llm_uses_explicit_fallback(self):
        def unavailable(*args):
            raise NarratorUnavailable("test outage")
        self.agent._ask_llm = unavailable
        result = self.send("uncertainty", {"uncertainty_reason": "missing_pointer"})
        self.assertTrue(result["fallback"])
        self.assertIn("Tracking", result["text"])

    def test_closed_round_rejects_late_events(self):
        self.send("game_ended", {"defused": False})
        calls = self.agent.llm_calls
        result = self.send("state", {"seconds_left": 9})
        self.assertFalse(result["say"])
        self.assertEqual(self.agent.llm_calls, calls)

    def test_observed_values_are_preserved_in_memory(self):
        self.send("inspection_result", {"target": "wire 2", "query": "blue", "observation": "No"})
        self.assertEqual(self.agent.sessions["round-1"].inspected_targets[-1]["observation"], "No")


if __name__ == "__main__":
    unittest.main()
