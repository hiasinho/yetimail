"""Move routing tests: private config fixtures and mocked subprocesses only."""

import contextlib
import io
import json
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest
from unittest.mock import patch


helper = runpy.run_path(str(Path(__file__).resolve().parents[1] / "bin/jitsmail-helper"))


class MoveHelperTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.config = Path(directory.name) / "config.toml"
        self.configure()

    def configure(self, aliases='', backend='imap'):
        self.config.write_text('[accounts.work]\ndefault = true\n'
                               f'[accounts.work.{backend}]\n'
                               '[accounts.work.mailbox.alias]\ninbox = "INBOX"\n' + aliases)

    def invoke(self, *args):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            status = helper['main']([*args, '--config', str(self.config)])
        self.assertEqual(len(output.getvalue().splitlines()), 1)
        return status, json.loads(output.getvalue())

    def test_move_argv_keeps_source_destination_and_id_literal(self):
        for source, destination in [('Sent Items', 'opaque/日本'),
                                    ('--from; dangerous', '--to; dangerous'),
                                    ('Inbox', 'Archive'), ('Archive', 'Inbox')]:
            with self.subTest(source=source), patch('subprocess.run', return_value=
                    subprocess.CompletedProcess([], 0, b'ignored', b'')) as run:
                status, result = self.invoke('move', '--account', 'work',
                    '--mailbox=' + source, '--destination=' + destination, '--id=--seen; dangerous')
                self.assertEqual((status, result), (0, {'id': '--seen; dangerous', 'destination': destination}))
                run.assert_called_once()
                self.assertEqual(run.call_args.args[0], ['himalaya', '--config=' + str(self.config),
                    '--account=work', 'message', 'move', '--from=' + source,
                    '--to=' + destination, '--', '--seen; dangerous'])
                self.assertEqual(run.call_args.kwargs['stdin'], subprocess.DEVNULL)
                self.assertEqual(run.call_args.kwargs['timeout'], 30)
                self.assertFalse(run.call_args.kwargs.get('shell', False))

    def test_omitted_source_uses_configured_inbox(self):
        with patch('subprocess.run', return_value=subprocess.CompletedProcess([], 0, b'', b'')) as run:
            self.assertEqual(self.invoke('move', '--id', '42', '--destination', 'Archive'),
                             (0, {'id': '42', 'destination': 'Archive'}))
            self.assertEqual(run.call_args.args[0], ['himalaya', '--config=' + str(self.config),
                             'message', 'move', '--to=Archive', '--', '42'])

    def test_alias_collisions_in_either_folder_fail_before_subprocess(self):
        self.configure('archive = "Elsewhere"\nsent = "Other"\n')
        for source, destination in [('INBOX', 'Archive'), ('Sent', 'Other Folder'),
                                    ('', 'ARCHIVE')]:
            with self.subTest(source=source), patch('subprocess.run') as run:
                status, result = self.invoke('move', '--id', '1', '--mailbox', source,
                                             '--destination', destination)
                self.assertEqual(status, 1)
                self.assertIn('alias', result['error'])
                run.assert_not_called()

    def test_same_folder_including_imap_inbox_and_implicit_source(self):
        for source, destination in [('Archive', 'Archive'), ('Inbox', 'INBOX'),
                                    ('INBOX', 'inbox'), ('', 'Inbox'), ('', 'INBOX')]:
            with self.subTest(source=source), patch('subprocess.run') as run:
                self.assertEqual(self.invoke('move', '--id', '1', '--mailbox', source,
                                            '--destination', destination)[0], 1)
                run.assert_not_called()
        self.config.write_text('[accounts.work]\ndefault = true\n'
                               '[accounts.work.mailbox.alias]\ninbox = "opaque-inbox"\n')
        with patch('subprocess.run') as run:
            self.assertEqual(self.invoke('move', '--id', '1', '--destination', 'opaque-inbox')[0], 1)
            run.assert_not_called()

    def test_non_imap_inbox_ids_do_not_gain_case_equivalence(self):
        self.config.write_text('[accounts.work]\ndefault = true\n[accounts.work.jmap]\n')
        with patch('subprocess.run', return_value=subprocess.CompletedProcess([], 0, b'', b'')):
            self.assertEqual(self.invoke('move', '--id', '1', '--mailbox', 'Inbox',
                                        '--destination', 'INBOX')[0], 0)

    def test_non_imap_destination_alias_case_change_is_rejected(self):
        self.configure(backend='jmap')
        with patch('subprocess.run') as run:
            status, result = self.invoke('move', '--id', '1', '--mailbox', 'Archive',
                                         '--destination', 'Inbox')
            self.assertEqual(status, 1)
            self.assertIn('alias', result['error'])
            run.assert_not_called()

    def test_unverifiable_configuration_fails_closed(self):
        for config in ('invalid toml', '[accounts.work]\ndefault = true\n'):
            self.config.write_text(config)
            with self.subTest(config=config), patch('subprocess.run') as run:
                self.assertEqual(self.invoke('move', '--id', '1', '--destination', 'Archive')[0], 1)
                run.assert_not_called()

    def test_validation_and_demo_are_offline(self):
        cases = [('move', '--destination', 'Archive'), ('move', '--id', '1'),
                 ('move', '--id', '1', '--destination', ''),
                 ('move', '--id', '1', '--destination', '  '),
                 ('move', '--id', '1', '--destination', 'Archive', '--seen'),
                 ('move', '--id', '1', '--destination', 'Archive', '--page', '1'),
                 ('list', '--destination', 'Archive')]
        with patch('subprocess.run') as run:
            for args in cases:
                for demo in ((), ('--demo',)):
                    with self.subTest(args=args, demo=demo):
                        self.assertEqual(self.invoke(*args, *demo)[0], 1)
            self.config.unlink()  # Demo must not even need local account configuration.
            self.assertEqual(self.invoke('move', '--demo', '--id', 'demo-1', '--destination', 'Archive'),
                             (0, {'id': 'demo-1', 'destination': 'Archive'}))
            for source, destination, message in [('', 'Inbox', 'demo-1'),
                    ('Inbox', 'missing', 'demo-1'), ('missing', 'Archive', 'demo-1'),
                    ('Inbox', 'Archive', 'missing')]:
                self.assertEqual(self.invoke('move', '--demo', '--id', message, '--mailbox', source,
                                             '--destination', destination)[0], 1)
            run.assert_not_called()

    def test_backend_failure_is_redacted_and_never_reports_moved(self):
        with patch('subprocess.run', return_value=subprocess.CompletedProcess([], 3, b'SECRET', b'PRIVATE')):
            self.assertEqual(self.invoke('move', '--id', '1', '--destination', 'Archive'),
                             (1, {'error': 'Himalaya failed (exit 3)'}))

    def test_flag_commands_remain_unchanged(self):
        for flag, operation, seen in [('--seen', 'add', True), ('--unseen', 'remove', False)]:
            with patch('subprocess.run', return_value=subprocess.CompletedProcess([], 0, b'', b'')) as run:
                self.assertEqual(self.invoke('mark', '--account', 'work', '--mailbox', 'Inbox',
                                             '--id', '42', flag), (0, {'id': '42', 'seen': seen}))
                self.assertEqual(run.call_args.args[0], ['himalaya', '--config=' + str(self.config),
                    '--account=work', 'flag', operation, '--flag', 'seen', '--mailbox=Inbox', '--', '42'])


if __name__ == '__main__':
    unittest.main()
