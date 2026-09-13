import os
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "tests" / "integration" / "harness.sh"


class IntegrationHarnessTests(unittest.TestCase):
    def test_isolates_home_guards_himalaya_and_cleans_children(self):
        script = r'''
set -euo pipefail
root=$1
quickshell=/bin/true
source "$root/tests/integration/harness.sh"
integration_init harness-regression
[[ ! -s $YETIMAIL_HIMALAYA_GUARD ]]
[[ -z $(PATH="$work/bin" command -v python3 || true) ]]
for path in "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" \
            "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR"; do
    [[ $path == "$work"/* && -d $path ]]
done
/usr/bin/sleep 30 &
child=$!
printf '%s\n' "$child" > "$YETIMAIL_CHILD_PIDS"
printf '%s\n%s\n' "$work" "$child"
'''
        result = subprocess.run(
            ["bash", "-c", script, "harness-test", str(ROOT)],
            check=True,
            capture_output=True,
            text=True,
            timeout=5,
        )
        work, child = result.stdout.strip().splitlines()
        self.assertFalse(Path(work).exists(), "temporary integration root survived cleanup")
        with self.assertRaises(ProcessLookupError):
            os.kill(int(child), 0)


if __name__ == "__main__":
    unittest.main()
