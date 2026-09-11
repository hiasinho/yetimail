"""Single deletion routing: synthetic configs and mocked subprocesses only."""
import contextlib
import io
import json
import os
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest
from unittest.mock import patch

helper = runpy.run_path(str(Path(__file__).resolve().parents[1] / 'bin/jitsmail-helper'))


class DeleteHelperTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        environment = patch.dict(os.environ, {'JITSMAIL_CACHE': '0'})
        environment.start()
        self.addCleanup(environment.stop)
        self.config = Path(directory.name) / 'config.toml'
        self.config.write_text('[accounts.work]\ndefault = true\n[accounts.work.imap]\n'
                               '[accounts.work.mailbox.alias]\ntrash = "Deleted Items"\n')

    def invoke(self, *args):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            status = helper['main'](['delete', '--config', str(self.config), *args])
        return status, json.loads(output.getvalue())

    def test_exact_argv_and_no_expunge(self):
        for mailbox in ('', 'INBOX', 'Deleted Items', '--folder; 日本'):
            with self.subTest(mailbox=mailbox), patch('subprocess.run', return_value=
                    subprocess.CompletedProcess([], 0, b'', b'')) as run:
                self.assertEqual(self.invoke('--account', 'work', '--id=--id; danger', '--mailbox=' + mailbox),
                                 (0, {'id': '--id; danger'}))
                run.assert_called_once()
                self.assertEqual(run.call_args.args[0], ['himalaya', '--config=' + str(self.config),
                    '--account=work', 'message', 'delete', *(['--mailbox=' + mailbox] if mailbox else []),
                    '--', '--id; danger'])
                self.assertEqual(run.call_args.kwargs['stdin'], subprocess.DEVNULL)
                self.assertFalse(run.call_args.kwargs.get('shell', False))

    def test_requires_explicit_account_nonempty_id_and_rejects_other_actions(self):
        with patch('subprocess.run') as run:
            for args in [(), ('--id', '1'), ('--account', ' ', '--id', '1'),
                         ('--account', 'work'), ('--account', 'work', '--id', ''),
                         ('--account', 'work', '--id', ' '),
                         *[('--account', 'work', '--id', '1', *extra) for extra in
                           [('--seen',), ('--page', '1'), ('--destination', 'Trash'), ('--id', '1', '2')]]]:
                for demo in ((), ('--demo',)):
                    self.assertEqual(self.invoke(*args, *demo)[0], 1, args)
            run.assert_not_called()

    def test_alias_guard_and_unverifiable_config(self):
        with patch('subprocess.run') as run:
            status, result = self.invoke('--account', 'work', '--id', '1', '--mailbox', 'Trash')
            self.assertEqual(status, 1)
            self.assertIn('alias', result['error'])
            self.config.write_text('invalid toml')
            self.assertEqual(self.invoke('--account', 'work', '--id', '1', '--mailbox', 'INBOX')[0], 1)
            run.assert_not_called()

    def test_demo_never_reads_config_or_invokes_backend(self):
        self.config.unlink()
        with patch('subprocess.run') as run, patch.dict(helper['main'].__globals__,
                check_literal_mailbox=lambda args: self.fail('demo config access')):
            self.assertEqual(self.invoke('--demo', '--account', 'Demo', '--id', 'demo-1', '--mailbox', 'Trash'),
                             (0, {'id': 'demo-1'}))
            for mailbox, message in [('missing', 'demo-1'), ('Trash', 'missing')]:
                self.assertEqual(self.invoke('--demo', '--account', 'Demo', '--id', message, '--mailbox', mailbox)[0], 1)
            run.assert_not_called()

    def test_failures_are_redacted(self):
        for outcome in [subprocess.CompletedProcess([], 3, b'SECRET', b'Trash unresolved PRIVATE'),
                        FileNotFoundError(), subprocess.TimeoutExpired('PRIVATE', 30)]:
            kwargs = {'side_effect': outcome} if isinstance(outcome, Exception) else {'return_value': outcome}
            with patch('subprocess.run', **kwargs) as run:
                status, result = self.invoke('--account', 'work', '--id', '1')
                self.assertEqual(status, 1)
                self.assertEqual(set(result), {'error'})
                self.assertNotIn('PRIVATE', result['error'])
                run.assert_called_once()


if __name__ == '__main__':
    unittest.main()
