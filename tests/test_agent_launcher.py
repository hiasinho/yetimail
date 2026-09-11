import json
import os
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
LAUNCHER = ROOT / "bin" / "yetimail-agent-launcher"
_loader = SourceFileLoader("yetimail_agent_launcher", str(LAUNCHER))
_spec = spec_from_loader(_loader.name, _loader)
agent_launcher = module_from_spec(_spec)
_loader.exec_module(agent_launcher)


class AgentLauncherTest(unittest.TestCase):
    def make_executable(self, path, content):
        path.write_text(content, encoding="utf-8")
        path.chmod(0o755)

    def test_prompt_uses_private_stdin_staging_not_desktop_launch_argv(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            runtime = base / "runtime"
            runtime.mkdir(mode=0o700)
            tools = base / "bin"
            tools.mkdir()
            launch_record = base / "launch.json"
            agent_record = base / "agent.json"

            self.make_executable(tools / "fake-agent", "#!/bin/sh\nexit 0\n")
            self.make_executable(tools / "omarchy-default-agent", "#!/bin/sh\nprintf '%s\\n' fake-agent\n")
            self.make_executable(
                tools / "omarchy-launch-tui",
                """#!/usr/bin/env python3
import json, os, sys
with open(os.environ["LAUNCH_RECORD"], "w", encoding="utf-8") as output:
    json.dump(sys.argv[1:], output)
os.execv(sys.argv[2], sys.argv[2:])
""",
            )
            self.make_executable(
                tools / "omarchy-agent",
                """#!/usr/bin/env python3
import json, os, sys
with open(os.environ["AGENT_RECORD"], "w", encoding="utf-8") as output:
    json.dump(sys.argv[1:], output)
""",
            )

            prompt = "Subject: private; $(touch /tmp/nope)\nBody with 'quotes' and ünicode " + "界" * 12000
            environment = os.environ.copy()
            environment.update({
                "PATH": str(tools) + os.pathsep + environment.get("PATH", ""),
                "XDG_RUNTIME_DIR": str(runtime),
                "LAUNCH_RECORD": str(launch_record),
                "AGENT_RECORD": str(agent_record),
            })
            result = subprocess.run(
                [str(LAUNCHER)], input=json.dumps({"prompt": prompt}) + "\n",
                text=True, capture_output=True, env=environment, timeout=20,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            for _ in range(100):
                if agent_record.exists():
                    break
                time.sleep(0.02)
            self.assertTrue(agent_record.exists())

            desktop_argv = json.loads(launch_record.read_text(encoding="utf-8"))
            self.assertNotIn(prompt, desktop_argv)
            self.assertFalse(any("Subject: private" in argument for argument in desktop_argv))
            self.assertEqual(desktop_argv[0], "--app-id=org.omarchy.agent")
            self.assertIn("--consume", desktop_argv)

            agent_argv = json.loads(agent_record.read_text(encoding="utf-8"))
            self.assertEqual(agent_argv, ["--inline", "--prompt", prompt])
            prompt_directory = runtime / "yetimail-agent"
            self.assertEqual(list(prompt_directory.iterdir()), [])

    def test_missing_default_agent_fails_without_staging_mail(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            runtime = base / "runtime"
            runtime.mkdir(mode=0o700)
            tools = base / "bin"
            tools.mkdir()
            self.make_executable(tools / "omarchy-default-agent", "#!/bin/sh\nexit 0\n")
            self.make_executable(tools / "omarchy-agent", "#!/bin/sh\nexit 0\n")
            self.make_executable(tools / "omarchy-launch-tui", "#!/bin/sh\nexit 0\n")
            environment = os.environ.copy()
            environment.update({"PATH": str(tools), "XDG_RUNTIME_DIR": str(runtime)})
            result = subprocess.run(
                ["/usr/bin/python3", str(LAUNCHER)], input='{"prompt":"private"}\n',
                text=True, capture_output=True, env=environment, timeout=10,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stderr.strip(), "Could not open Ask agent.")
            self.assertFalse((runtime / "yetimail-agent").exists())

    def test_write_failure_removes_staged_mail(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            directory.chmod(0o700)
            with mock.patch.object(agent_launcher, "configured_agent_is_available", return_value=True), \
                    mock.patch.object(agent_launcher, "private_runtime_directory", return_value=directory), \
                    mock.patch.object(agent_launcher.os, "fsync", side_effect=OSError("full")):
                with self.assertRaises(OSError):
                    agent_launcher.stage_prompt("private message")
            self.assertEqual(list(directory.iterdir()), [])

    def test_rejects_non_private_runtime_directory(self):
        with tempfile.TemporaryDirectory() as temporary:
            runtime = Path(temporary) / "runtime"
            runtime.mkdir(mode=0o755)
            environment = os.environ.copy()
            environment["XDG_RUNTIME_DIR"] = str(runtime)
            result = subprocess.run(
                [str(LAUNCHER), "--consume", str(runtime / "prompt-bad")],
                text=True, capture_output=True, env=environment, timeout=10,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stderr.strip(), "Could not open Ask agent.")


if __name__ == "__main__":
    unittest.main()
