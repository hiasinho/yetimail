import json
import sys

path, scenario = sys.argv[1:]
with open(path) as stream:
    events = [json.loads(line) for line in stream]
starts = [e for e in events if e['event'] == 'start']
lists = [e for e in starts if e['operation'] == 'list']
# Exact calls catch implicit accounts, duplicate probes, and accidental pagination.
expected = [('A', True, 'old'), ('A', False, 'old')]
if scenario in ('switch', 'stale'):
    # Returning to a fresh in-memory folder snapshot is synchronous and does
    # not launch another network revalidation.
    expected += [('B', True, 'old'), ('B', False, 'old')]
elif scenario == 'warm':
    expected += [('B', True, 'old'), ('C', True, 'old'), ('B', False, 'old'), ('C', False, 'old')]
elif scenario in ('refresh', 'config'):
    expected += [('A', False, 'old')]
    if scenario == 'config':
        expected += [('A', True, 'new'), ('A', False, 'new')]
actual = [(e['account'], e['probe'], 'new' if e['config'].endswith('new.toml') else 'old') for e in lists]
assert actual == expected, (scenario, actual, expected)
assert all(e['page'] == '1' and not e.get('mailbox') for e in lists), lists
folders = [e for e in starts if e['operation'] == 'folders']
assert [e['account'] for e in folders] == (['A', 'B', 'C'] if scenario == 'warm' else []), folders
reads = [e for e in starts if e['operation'] == 'read']
assert [e['id'] for e in reads] == (['A-1'] if scenario == 'refresh' else []), reads
if scenario == 'refresh':
    list_ends = [e for e in events if e['operation'] == 'list' and e['event'] == 'end']
    read_end = next(e for e in events if e['operation'] == 'read' and e['event'] == 'end')
    assert lists[-1]['time'] < read_end['time'] < list_ends[-1]['time'], 'read blocked on refresh'
assert len(starts) * 2 == len(events), ('unfinished fixture calls', events)
print('INSTANT_CALLS_OK', scenario)
