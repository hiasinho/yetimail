import json
import os
import sys
import time

# Discard the production helper path. Config paths are opaque synthetic strings.
operation, *args = sys.argv[2:]
options = {'probe': False}
while args:
    arg = args.pop(0)
    if arg == '--cache-only':
        options['probe'] = True
    elif arg.startswith('--mailbox='):
        options['mailbox'] = arg.split('=', 1)[1]
    elif arg in ('--account', '--config', '--page', '--id') and args:
        options[arg[2:]] = args.pop(0)
    else:
        raise RuntimeError('FORBIDDEN argument: ' + arg)
if operation not in ('list', 'folders', 'read'):
    raise RuntimeError('FORBIDDEN operation: ' + operation)
assert options.get('account') in ('A', 'B', 'C')
assert options.get('config') in ('/synthetic/old.toml', '/synthetic/new.toml')

def log(event):
    with open(os.environ['YETIMAIL_CALLS'], 'a') as stream:
        stream.write(json.dumps(dict(event=event, operation=operation,
                                    time=time.monotonic(), **options)) + '\n')

log('start')
account = options['account']
version = 'new' if options['config'].endswith('new.toml') else 'old'
if operation == 'list':
    time.sleep(0.12 if options['probe'] else 0.55)
    value = dict(account=account, page=int(options['page']), hasNext=False,
                 messages=[dict(id=account + '-1', subject=account + ':' + version + ':live', unread=True)])
    if options['probe']:
        hit = os.environ['YETIMAIL_SCENARIO'] == 'hit'
        value['messages'][0]['subject'] = account + ':' + version + ':disk'
        result = dict(hit=hit, value=value if hit else None)
    else:
        result = value
elif operation == 'folders':
    time.sleep(0.1)
    result = dict(folders=[dict(id='INBOX', name='Inbox', role='inbox'),
                           dict(id='Archive', name='Archive', role='archive')])
else:
    time.sleep(0.05)
    result = dict(id=options['id'], body='offline fixture')
log('end')
print(json.dumps(result))
