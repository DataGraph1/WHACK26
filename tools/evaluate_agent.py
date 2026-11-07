"""Compare a local narrator model on observed game events without using speech credits."""
import argparse
import os
import statistics
import sys
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--model', default='qwen2.5:3b')
args = parser.parse_args()
os.environ['OLLAMA_MODEL'] = args.model
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'narrator'))
from agent_api import NarratorAgent, validate_event

agent = NarratorAgent()
agent._speech = lambda text, mood: ''
cases = [
    ('round_started', {'lives': 3, 'seconds_left': 180,
        'modules': ['LINK RECOVERY', 'WIRES'],
        'mission': 'Disarm every module using the field guide and both hands'}, None),
    ('focus', {'target': 'wire 2', 'seconds_left': 145, 'lives': 3,
        'dwell_seconds': 1.25}, None),
    ('inspection_result', {'target': 'wire 2', 'query': 'blue',
        'observation': 'No', 'lives': 3, 'seconds_left': 130}, None),
    ('result', {'target': 'wire 2', 'lives': 2, 'seconds_left': 110}, 'wrong'),
    ('state', {'seconds_left': 29, 'lives': 2, 'right_hand_visible': True,
        'idle_seconds': 5}, None),
    ('uncertainty', {'uncertainty_reason': 'right_hand_missing', 'lives': 2}, None),
]
latencies = []
for index, (kind, context, result) in enumerate(cases):
    raw = {'session_id': 'quality-check', 'event_id': str(index), 'game': 'WIRES',
           'kind': kind, 'context': context}
    if result:
        raw['result'] = result
    reply = agent.handle(validate_event(raw))
    if reply['say'] and not reply.get('fallback') and not reply.get('policy_guarded'):
        latencies.append(reply['processing_ms'])
    source = 'fallback' if reply.get('fallback') else 'guard' if reply.get('policy_guarded') else 'model'
    print(f"{kind}: trigger={reply['trigger']} source={source} "
          f"ms={reply['processing_ms']} text={reply['text']!r} "
          f"reason={reply.get('fallback_reason', '')!r}")
print('spoken', len(latencies), 'median_ms', statistics.median(latencies) if latencies else 0)
