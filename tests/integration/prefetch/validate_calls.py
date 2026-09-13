import json
import sys

path, scenario = sys.argv[1:]
with open(path) as stream:
    events = [json.loads(line) for line in stream]
reads = [e for e in events if e['operation'] == 'read']
starts = [e for e in reads if e['event'] == 'start']
expected = {'debounce': list('bcd'), 'failure': list('abc'), 'page': list('abc'),
            'different': list('ae'), 'pending-withdrawal': []}.get(scenario, ['a'])
assert [e['id'] for e in starts] == expected, (scenario, 'duplicate/stale/missing read', starts)
active = set()
for event in reads:
    if event['event'] == 'start':
        assert event['id'] not in active, ('duplicate in-flight ID', event)
        active.add(event['id'])
        assert len(active) <= (2 if scenario == 'different' else 1), ('parallel background reads', reads)
    else:
        active.remove(event['id'])
assert not active, ('unfinished processes', active)
if scenario == 'different':
    background_end = next(e['time'] for e in reads if e['id'] == 'a' and e['event'] == 'end')
    assert starts[1]['time'] < background_end, 'foreground waited for unrelated background process'
assert all(e.get('account') == 'fixture' and not e.get('config') and not e.get('mailbox')
           for e in starts), ('mutable background command context', starts)
print('PREFETCH_CALLS_OK', scenario, ''.join(e['id'] for e in starts) or '(none)')
