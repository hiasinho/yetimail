import json
import os
import sys
import time

# Ignore the helper path, never execute it or inspect mail configuration.
operation, *args = sys.argv[2:]
options = {}
while args:
    arg = args.pop(0)
    if arg.startswith('--mailbox='):
        options['mailbox'] = arg.split('=', 1)[1]
    elif arg in ('--account', '--config', '--id', '--page') and args:
        options[arg[2:]] = args.pop(0)
    else:
        raise RuntimeError('FORBIDDEN argument: ' + arg)
if operation not in ('list', 'read', 'folders'):
    raise RuntimeError('FORBIDDEN operation: ' + operation)

def log(event):
    with open(os.environ['YETIMAIL_CALLS'], 'a') as stream:
        stream.write(json.dumps(dict(event=event, operation=operation,
                                    time=time.monotonic(), **options)) + '\n')

log('start')
if operation == 'read':
    time.sleep(0.65)
    result = dict(id=options['id'], body='fixture ' + options.get('account', ''))
    if os.environ['YETIMAIL_SCENARIO'] == 'failure':
        result = dict(error='PRIVATE background failure')
elif operation == 'list':
    result = dict(page=int(options['page']), hasNext=True,
                  messages=[dict(id=x, subject=x, unread=True) for x in 'abcde'])
else:
    result = dict(folders=[dict(id='Archive', name='Archive', role='archive')])
log('end')
print(json.dumps(result))
sys.exit(1 if 'error' in result else 0)
