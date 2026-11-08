"""Stateful event decisions without calling Ollama or ElevenLabs."""

import unittest
from unittest.mock import patch
import urllib.error

try:
    from .agent_api import NarratorAgent, NarratorUnavailable, Session, validate_event
except ImportError:
    from agent_api import NarratorAgent, NarratorUnavailable, Session, validate_event


class OllamaErrorTest(unittest.TestCase):
    def setUp(self):
        self.agent = NarratorAgent()
        self.event = validate_event({"session_id": "test", "event_id": "1", "game": "wires",
                                     "kind": "result", "result": "wrong", "context": {}})

    def ask(self):
        return self.agent._ask_llm(self.event, Session(), 1)

    def test_missing_model_has_pull_command(self):
        with patch("urllib.request.urlopen", side_effect=urllib.error.HTTPError(
                "http://127.0.0.1", 404, "not found", {}, None)):
            with self.assertRaisesRegex(NarratorUnavailable, "ollama pull"):
                self.ask()

    def test_unreachable_server_is_distinct_from_timeout(self):
        with patch("urllib.request.urlopen", side_effect=urllib.error.URLError("connection refused")):
            with self.assertRaisesRegex(NarratorUnavailable, "Cannot reach Ollama"):
                self.ask()
        with patch("urllib.request.urlopen", side_effect=TimeoutError("timed out")):
            with self.assertRaisesRegex(NarratorUnavailable, "timed out"):
                self.ask()


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
        self.assertIn("30 seconds", warning["text"])
        self.assertTrue(warning["policy_guarded"])
        self.clock.now = 134
        self.assertFalse(self.send("state", {"seconds_left": 27})["say"])
        self.clock.now = 140
        self.assertEqual(self.send("state", {"seconds_left": 9})["trigger"], "time_warning")

    def test_locked_target_still_gets_pacing_without_right_hand(self):
        self.send("round_started", {"lives": 3})
        self.clock.now = 112
        prompt = self.send("state", {"idle_seconds": 12, "right_hand_visible": False,
                                     "left_hand_visible": True, "target_locked": True,
                                     "locked_target": "wire 2"})
        self.assertEqual(prompt["trigger"], "hesitation")
        self.assertTrue(prompt["say"])

    def test_intermediate_correct_stages_do_not_flood_audio(self):
        self.send("round_started", {"lives": 3})
        self.clock.now = 102
        quiet = self.send("result", {"module_solved": False}, result="correct",
                          game="MEMORY", action="press button 2")
        self.assertFalse(quiet["say"])
        self.assertIn("Stage accepted", quiet["reason"])
        self.clock.now = 109
        spoken = self.send("result", {"module_solved": False}, result="correct",
                           game="MEMORY", action="press button 1")
        self.assertTrue(spoken["say"])
        self.assertTrue(spoken["text"].startswith("Correct!"))

    def test_last_life_warning_overrides_stage_quiet(self):
        self.send("round_started", {"lives": 3})
        self.clock.now = 102
        result = self.send("result", {"module_solved": False, "lives": 1},
                           result="correct", game="SIMON SAYS")
        self.assertTrue(result["say"])
        self.assertIn("One life remains", result["text"])

    def test_uncertainty_has_cooldown_and_result_preserves_last_life(self):
        self.send("round_started", {"lives": 3})
        self.clock.now = 110
        uncertain = self.send("uncertainty", {"uncertainty_reason": "right_hand_missing"})
        self.assertEqual(uncertain["trigger"], "uncertainty")
        self.assertTrue(uncertain["say"])
        self.assertIn("both hands", uncertain["text"])
        self.assertTrue(uncertain["policy_guarded"])
        self.clock.now = 111
        self.assertFalse(self.send("uncertainty", {"uncertainty_reason": "right_hand_missing"})["say"])
        self.clock.now = 120
        result = self.send("result", {"lives": 1}, result="wrong", action="cut wire 2")
        self.assertEqual(result["mood"], "urgent")
        self.assertTrue(result["text"].startswith("Wrong choice."))
        self.assertIn("One life remains", result["text"])
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
        result = self.send("focus", {"target": "wire 2"})
        self.assertTrue(result["fallback"])
        self.assertIn("wire 2 is under your pointer", result["text"])
        self.assertEqual(result["observed_target"], "wire 2")

    def test_closed_round_rejects_late_events(self):
        self.send("game_ended", {"defused": False})
        calls = self.agent.llm_calls
        result = self.send("state", {"seconds_left": 9})
        self.assertFalse(result["say"])
        self.assertEqual(self.agent.llm_calls, calls)

    def test_observed_values_are_preserved_in_memory(self):
        self.send("inspection_result", {"target": "wire 2", "query": "blue", "observation": "No"})
        self.assertEqual(self.agent.sessions["round-1"].inspected_targets[-1]["observation"], "No")

    def test_inspection_speaks_named_game_fact(self):
        reply = self.send("inspection_result", {"target": "wire 2", "query": "blue", "observation": "No"})
        self.assertTrue(reply["say"])
        self.assertEqual(reply["text"], "No, wire 2 is not blue.")
        self.assertEqual(reply["decision_source"], "guard")
        self.assertIn("wire 2: blue = No", reply["evidence"])

    def test_pending_action_can_use_memory_before_confirmation(self):
        self.send("inspection_result", {"target": "wire 2", "query": "blue", "observation": "No"})
        reply = self.send("pending_action", {"target": "wire 2", "pending_id": "p1"},
                          game="wires", action="cut wire 2")
        self.assertEqual(reply["decision_source"], "model")
        self.assertEqual(reply["observed_pending_id"], "p1")
        self.assertIn("wire 2: blue = No", reply["evidence"])

    def test_pending_action_quiets_if_model_unavailable(self):
        def unavailable(*args):
            raise NarratorUnavailable("test outage")
        self.agent._ask_llm = unavailable
        reply = self.send("pending_action", {"target": "wire 2", "pending_id": "p2"})
        self.assertFalse(reply["say"])
        self.assertEqual(reply["decision_source"], "fallback")

    def test_model_question_is_replaced_with_safe_line(self):
        self.agent._ask_llm = lambda *args: {
            "say": True, "text": "What is this round about?", "mood": "cheerful",
            "reason": "Need more information",
        }
        result = self.send("result", {"lives": 2}, result="correct")
        self.assertTrue(result["fallback"])
        self.assertNotIn("?", result["text"])
        self.assertTrue(result["text"].endswith("."))

    def test_current_timer_overrides_stale_memory(self):
        self.send("result", {"seconds_left": 110, "lives": 2}, result="wrong")
        result = self.send("state", {"seconds_left": 29, "lives": 2})
        self.assertIn("30 seconds", result["text"])
        self.assertNotIn("110", result["text"])

    def test_result_rejects_invented_deadline_and_life(self):
        self.agent._ask_llm = lambda *args: {
            "say": True, "text": "Time's up! One life left. Inspect wire 2 again.",
            "mood": "tense", "reason": "Guessed status",
        }
        result = self.send("result", {"seconds_left": 110, "lives": 2}, result="wrong")
        self.assertTrue(result["fallback"])
        self.assertNotIn("Time's up", result["text"])
        self.assertNotIn("One life", result["text"])

    def test_result_does_not_repeat_preconfirmation_cue(self):
        self.agent._ask_llm = lambda *args: {
            "say": True, "text": "Inspect wire 2 again before confirming.",
            "mood": "concerned", "reason": "Repeated cue",
        }
        self.send("pending_action", {"target": "wire 2", "pending_id": "one"}, game="WIRES")
        result = self.send("result", {"target": "wire 2", "target_reusable": False},
                           result="wrong", game="WIRES")
        self.assertTrue(result["fallback"])
        self.assertIn("remaining targets", result["text"])

    def test_wrong_result_does_not_send_player_away_from_active_module(self):
        self.agent._ask_llm = lambda *args: {
            "say": True, "text": "Oops, try another module.",
            "mood": "concerned", "reason": "Suggested switching",
        }
        result = self.send("result", {"module_solved": False}, result="wrong")
        self.assertTrue(result["fallback"])
        self.assertIn("unfinished module", result["fallback_reason"])
        self.assertNotIn("another module", result["text"])

    def test_confirmed_mistake_is_not_blame_on_camera(self):
        self.agent._ask_llm = lambda *args: {
            "say": True, "text": "Check your grip and gesture next time.",
            "mood": "concerned", "reason": "Guessed tracking failure",
        }
        result = self.send("result", {"module_solved": False}, result="wrong")
        self.assertTrue(result["fallback"])
        self.assertIn("confirmed puzzle mistake", result["fallback_reason"])

    def test_cut_wire_cannot_be_reused(self):
        self.agent._ask_llm = lambda *args: {
            "say": True, "text": "Double check it before cutting again.",
            "mood": "concerned", "reason": "Suggested reusing target",
        }
        result = self.send("result", {"module_solved": False, "target_reusable": False},
                           result="wrong")
        self.assertTrue(result["fallback"])
        self.assertIn("unavailable target", result["fallback_reason"])

    def test_model_observation_omits_counters(self):
        event = validate_event({"session_id": "r", "game": "wires", "kind": "result",
            "result": "wrong", "context": {"target": "wire 2", "seconds_left": 110,
            "lives": 2, "strikes": 1}})
        observation = self.agent._model_observation(event)["context"]
        self.assertEqual(observation, {"target": "wire 2"})


if __name__ == "__main__":
    unittest.main()
